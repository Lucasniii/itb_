-- ════════════════════════════════════════════════════════════════
--  ITB.BERICHTE – Abbild des Datenbankstands
--  Supabase-Projekt jkxxgvhknswhbayvmmoc (eu-central-1)
--
--  Das hier ist DOKUMENTATION, kein Migrations-Runner: es gibt in
--  diesem Repo keine Supabase-CLI und keine Verknuepfung zum Projekt.
--  Die Datei beschreibt den Stand so, wie er angewendet ist, und ist
--  in dieser Reihenfolge auf einer leeren Datenbank lauffaehig.
--
--  Grundregeln, die hier nicht verhandelt werden:
--   * RLS auf jeder Tabelle, jede Policy ausschliesslich to authenticated.
--   * anon hat weder Policy noch Grant – die App ist oeffentlich gehostet.
--   * Die Freigabepflicht steht im Trigger, nicht in der Oberflaeche.
--
--  Nach jeder Schemaaenderung diese Datei nachziehen, sonst driftet sie
--  vom echten Stand weg – und das waere schlimmer als gar keine Datei.
-- ════════════════════════════════════════════════════════════════


-- ── Generische Helfer ─────────────────────────────────────────

-- Profil bei Registrierung automatisch anlegen.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ── profiles: haengt an auth.users, haelt Anzeigename und Rolle ──

create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text,
  display_name  text,
  created_at    timestamptz not null default now(),
  role          text not null default 'user' check (role in ('user', 'admin'))
);

comment on column public.profiles.role is
  'user  = darf Eintraege einreichen (landen in der Freigabe),
   admin = darf freigeben/ablehnen und Rollen vergeben.';

alter table public.profiles enable row level security;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Rollen-Lookup fuer Policies. SECURITY DEFINER, damit die Policies die Rolle
-- lesen koennen, ohne rekursiv gegen die profiles-Policies zu laufen.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

comment on function public.is_admin() is
  'SECURITY DEFINER, damit Policies die Rolle lesen koennen, ohne rekursiv
   gegen die profiles-Policies zu laufen. Liest ausschliesslich die Zeile des
   angemeldeten Nutzers und gibt nur true/false zurueck – keine Inhalte.';

-- Rollenwechsel nur durch Admins, letzter Admin bleibt Admin.
create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role is distinct from old.role then
    -- auth.uid() is null = Service-Role/SQL-Editor. Dieser Weg umgeht RLS
    -- ohnehin und bleibt der Notausgang, falls es keinen Admin mehr gibt.
    if auth.uid() is not null and not public.is_admin() then
      raise exception 'Nur Admins duerfen Rollen aendern' using errcode = '42501';
    end if;
    if old.role = 'admin' and new.role <> 'admin'
       and (select count(*) from public.profiles where role = 'admin') <= 1 then
      raise exception 'Der letzte Admin kann nicht entzogen werden' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_role_guard
  before update on public.profiles
  for each row execute function public.guard_profile_role();

-- Profile sind fuer alle Angemeldeten lesbar (damit "angelegt von" anzeigbar ist).
create policy profiles_select_authenticated on public.profiles
  for select to authenticated using (true);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_update_admin on public.profiles
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));


-- ── decoder_features: eigene Beschreibungen zu Decoder-Positionen ──

create table if not exists public.decoder_features (
  id           uuid primary key default gen_random_uuid(),
  type         text not null check (type in (
                 'ZCONFIG','ZCONFIG2','ZCONFIG3','ZCONFIG4',
                 'ZVALUE','ZVALUE2','DATACONFIG')),
  position     integer not null check (position between 1 and 999),
  customer     text not null default '' check (char_length(customer) <= 100),
  description  text not null check (char_length(description) between 1 and 1000),
  notes        text not null default '' check (char_length(notes) <= 1000),
  created_by   uuid references auth.users(id) on delete set null,
  updated_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  status       text not null default 'pending'
                 check (status in ('pending','approved','rejected')),
  reviewed_by  uuid references auth.users(id),
  reviewed_at  timestamptz,
  review_note  text not null default '' check (char_length(review_note) <= 500)
);

comment on column public.decoder_features.status is
  'pending = eingereicht und wartet auf Freigabe, approved = freigegeben (nur
   dieser Stand wird im Decoder angezeigt), rejected = abgelehnt.';

alter table public.decoder_features enable row level security;

-- Eindeutig ist nur der freigegebene Stand. Dadurch kann zu einer bereits
-- freigegebenen Position ein Aenderungsvorschlag offen liegen, ohne die live
-- sichtbare Beschreibung zu verdraengen; pro Person ein offener Vorschlag.
create unique index if not exists decoder_features_approved_key
  on public.decoder_features (type, "position") where status = 'approved';
create unique index if not exists decoder_features_pending_key
  on public.decoder_features (type, "position", created_by) where status = 'pending';
create index if not exists decoder_features_lookup_idx
  on public.decoder_features (type, "position");

-- Kern der Freigabepflicht: wer kein Admin ist, kann die Statusfelder nicht
-- setzen – unabhaengig davon, was der Client schickt.
create or replace function public.guard_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid    := auth.uid();
  -- SQL-Editor/service_role bleibt der dokumentierte Recovery-Weg.
  v_admin boolean := auth.uid() is null or public.is_admin();
  v_meta  text[]  := array[
    'id','status','reviewed_by','reviewed_at','review_note',
    'created_by','created_at','updated_by','updated_at'
  ];
begin
  if tg_op = 'INSERT' then
    if v_uid is not null then
      -- Identitaet und Auditfelder niemals dem Browser glauben.
      new.created_by := v_uid;
      new.updated_by := v_uid;
      new.created_at := now();
      new.updated_at := now();
    end if;

    if v_uid is null then
      -- Service/SQL-Editor darf Status fuer Migration/Recovery vorgeben.
      return new;
    elsif v_admin then
      new.status := 'approved';
      new.reviewed_by := v_uid;
      new.reviewed_at := now();
      new.review_note := '';
    else
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.review_note := '';
    end if;
    return new;
  end if;

  -- id/created_by/created_at sind fuer authentifizierte Aufrufer unveraenderlich.
  -- auth.uid() IS NULL bleibt wegen ON DELETE SET NULL und Recovery erlaubt.
  if v_uid is not null and (
       new.id         is distinct from old.id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'id, created_by und created_at sind unveraenderlich'
      using errcode = '42501';
  end if;

  if v_uid is not null then
    new.updated_by := v_uid;
  end if;

  if v_admin then
    if v_uid is not null and new.status is distinct from old.status then
      new.reviewed_by := v_uid;
      new.reviewed_at := now();
    end if;
    return new;
  end if;

  -- Nicht-Admins koennen Statusfelder nie selbst setzen; jede inhaltliche
  -- Aenderung geht (zurueck) in die Freigabe.
  if to_jsonb(new) - v_meta is distinct from to_jsonb(old) - v_meta then
    new.status := 'pending';
    new.review_note := '';
    new.reviewed_by := null;
    new.reviewed_at := null;
  else
    new.status := old.status;
    new.review_note := old.review_note;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

comment on function public.guard_review() is
  'Erzwingt die Freigabepflicht serverseitig fuer decoder_features: wer kein Admin
   ist, kann status, reviewed_by/at und review_note nicht selbst setzen. Identitaet
   und Auditfelder werden serverseitig gesetzt, id/created_by/created_at sind
   unveraenderlich.';

create trigger decoder_features_review
  before insert or update on public.decoder_features
  for each row execute function public.guard_review();

create trigger decoder_features_touch
  before update on public.decoder_features
  for each row execute function public.touch_updated_at();

-- Offene Vorschlaege bleiben zwischen Verfasser:in und Admins.
create policy decoder_features_select on public.decoder_features
  for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or (select public.is_admin()));

create policy decoder_features_insert on public.decoder_features
  for insert to authenticated
  with check (created_by = (select auth.uid()) and updated_by = (select auth.uid()));

-- Freigegebenes aendert nur ein Admin; alle anderen schlagen eine neue Zeile vor.
create policy decoder_features_update on public.decoder_features
  for update to authenticated
  using ((select public.is_admin())
         or (created_by = (select auth.uid()) and status <> 'approved'))
  with check (((select public.is_admin()) and updated_by = (select auth.uid()))
         or (created_by = (select auth.uid())
             and updated_by = (select auth.uid())
             and status <> 'approved'));

create policy decoder_features_delete on public.decoder_features
  for delete to authenticated
  using ((select public.is_admin())
         or (created_by = (select auth.uid()) and status <> 'approved'));

-- Freigabe in einem Schritt, damit Ersetzen und Freigeben atomar passieren.
create or replace function public.approve_decoder_feature(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_type text;
  v_pos  integer;
begin
  if not public.is_admin() then
    raise exception 'Nur Admins duerfen Eintraege freigeben' using errcode = '42501';
  end if;

  select type, "position" into v_type, v_pos
    from public.decoder_features where id = p_id;
  if v_type is null then
    raise exception 'Eintrag nicht gefunden' using errcode = 'P0002';
  end if;

  -- Der bisher freigegebene Stand dieser Position wird ersetzt.
  delete from public.decoder_features
   where type = v_type and "position" = v_pos and status = 'approved' and id <> p_id;

  update public.decoder_features
     set status = 'approved', review_note = '', updated_by = auth.uid(),
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
end;
$$;

comment on function public.approve_decoder_feature(uuid) is
  'Freigabe in einem Schritt: ersetzt den bisher freigegebenen Stand derselben
   (type, position) durch den freigegebenen Vorschlag. SECURITY DEFINER nur,
   damit beides atomar passiert – die Admin-Pruefung steht in der Funktion.';


-- ── Rechte ────────────────────────────────────────────────────

-- Trigger-Funktionen brauchen keinen REST-Zugang; Trigger feuern unabhaengig
-- vom EXECUTE-Recht (das wird beim Anlegen des Triggers geprueft).
revoke all on function public.handle_new_user()    from public, anon, authenticated;
revoke all on function public.touch_updated_at()   from public, anon, authenticated;
revoke all on function public.guard_review()       from public, anon, authenticated;
revoke all on function public.guard_profile_role() from public, anon, authenticated;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

revoke all on function public.approve_decoder_feature(uuid) from public, anon;
grant execute on function public.approve_decoder_feature(uuid) to authenticated;

-- Zweites Netz unter RLS: anon hatte durch die Supabase-Standardrechte noch
-- SELECT/INSERT/UPDATE/DELETE auf allen Tabellen. Ein einziges versehentlich
-- deaktiviertes RLS haette die Daten sofort weltweit geoeffnet.
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;

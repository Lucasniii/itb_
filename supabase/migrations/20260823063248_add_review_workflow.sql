-- ── Freigabe-Status fuer alle Wissensinhalte ───────────────────
alter table public.decoder_features
  add column if not exists status      text        not null default 'pending',
  add column if not exists reviewed_by uuid        references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text        not null default '';

alter table public.decoder_features drop constraint if exists decoder_features_status_check;
alter table public.decoder_features
  add constraint decoder_features_status_check check (status in ('pending','approved','rejected'));
alter table public.decoder_features drop constraint if exists decoder_features_review_note_check;
alter table public.decoder_features
  add constraint decoder_features_review_note_check check (char_length(review_note) <= 500);

alter table public.orakel_entries
  add column if not exists status      text        not null default 'pending',
  add column if not exists reviewed_by uuid        references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text        not null default '';

alter table public.orakel_entries drop constraint if exists orakel_entries_status_check;
alter table public.orakel_entries
  add constraint orakel_entries_status_check check (status in ('pending','approved','rejected'));
alter table public.orakel_entries drop constraint if exists orakel_entries_review_note_check;
alter table public.orakel_entries
  add constraint orakel_entries_review_note_check check (char_length(review_note) <= 500);

comment on column public.decoder_features.status is
  'pending = eingereicht und wartet auf Freigabe, approved = freigegeben (nur
   dieser Stand wird im Decoder angezeigt), rejected = abgelehnt.';

-- Bestand (falls vorhanden) bleibt sichtbar.
update public.decoder_features set status = 'approved' where status = 'pending';
update public.orakel_entries   set status = 'approved' where status = 'pending';

-- ── Eindeutigkeit nur noch fuer den freigegebenen Stand ────────
-- Damit kann zu einer bereits freigegebenen Position ein Aenderungsvorschlag
-- offen liegen, ohne die live sichtbare Beschreibung zu verdraengen.
alter table public.decoder_features drop constraint if exists decoder_features_type_position_key;
create unique index if not exists decoder_features_approved_key
  on public.decoder_features (type, "position") where status = 'approved';
create unique index if not exists decoder_features_pending_key
  on public.decoder_features (type, "position", created_by) where status = 'pending';

-- ── Statusfelder gegen Selbstfreigabe absichern ────────────────
create or replace function public.guard_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin boolean := public.is_admin();
  v_meta  text[]  := array['id','status','reviewed_by','reviewed_at','review_note',
                           'created_by','created_at','updated_by','updated_at'];
begin
  if tg_op = 'INSERT' then
    if v_admin then
      -- Admins geben ihre eigenen Eintraege direkt frei.
      new.status := 'approved'; new.reviewed_by := auth.uid(); new.reviewed_at := now();
    else
      new.status := 'pending'; new.reviewed_by := null; new.reviewed_at := null;
      new.review_note := '';
    end if;
    return new;
  end if;

  if v_admin then
    if new.status is distinct from old.status then
      new.reviewed_by := auth.uid();
      new.reviewed_at := now();
    end if;
    return new;
  end if;

  -- Nicht-Admins koennen Statusfelder nie selbst setzen; jede inhaltliche
  -- Aenderung geht (zurueck) in die Freigabe.
  if to_jsonb(new) - v_meta is distinct from to_jsonb(old) - v_meta then
    new.status := 'pending'; new.review_note := '';
    new.reviewed_by := null; new.reviewed_at := null;
  else
    new.status := old.status;           new.review_note := old.review_note;
    new.reviewed_by := old.reviewed_by; new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

comment on function public.guard_review() is
  'Erzwingt die Freigabepflicht serverseitig: wer kein Admin ist, kann status,
   reviewed_by/at und review_note nicht selbst setzen – unabhaengig davon, was
   der Client schickt.';

drop trigger if exists decoder_features_review on public.decoder_features;
create trigger decoder_features_review
  before insert or update on public.decoder_features
  for each row execute function public.guard_review();

drop trigger if exists orakel_entries_review on public.orakel_entries;
create trigger orakel_entries_review
  before insert or update on public.orakel_entries
  for each row execute function public.guard_review();

-- ── Policies: jeder darf einreichen, nur Admins geben frei ─────
drop policy if exists decoder_features_select on public.decoder_features;
create policy decoder_features_select on public.decoder_features
  for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or (select public.is_admin()));

drop policy if exists decoder_features_update on public.decoder_features;
create policy decoder_features_update on public.decoder_features
  for update to authenticated
  using ((select public.is_admin()) or (created_by = auth.uid() and status <> 'approved'))
  with check (updated_by = auth.uid());

drop policy if exists decoder_features_delete on public.decoder_features;
create policy decoder_features_delete on public.decoder_features
  for delete to authenticated
  using ((select public.is_admin()) or (created_by = auth.uid() and status <> 'approved'));

drop policy if exists orakel_entries_select on public.orakel_entries;
create policy orakel_entries_select on public.orakel_entries
  for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or (select public.is_admin()));

drop policy if exists orakel_entries_update on public.orakel_entries;
create policy orakel_entries_update on public.orakel_entries
  for update to authenticated
  using ((select public.is_admin()) or (created_by = auth.uid() and status <> 'approved'))
  with check (updated_by = auth.uid());

drop policy if exists orakel_entries_delete on public.orakel_entries;
create policy orakel_entries_delete on public.orakel_entries
  for delete to authenticated
  using ((select public.is_admin()) or (created_by = auth.uid() and status <> 'approved'));

-- ── Freigabe einer Decoder-Beschreibung ────────────────────────
create or replace function public.approve_decoder_feature(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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

revoke all on function public.approve_decoder_feature(uuid) from public, anon;
grant execute on function public.approve_decoder_feature(uuid) to authenticated;

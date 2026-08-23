-- ════════════════════════════════════════════════════════════════
--  ITB.BERICHTE – Basisschema
--  Zugriff ausschliesslich fuer angemeldete Nutzer (authenticated).
--  Kein anon-Zugriff: die App ist oeffentlich gehostet.
-- ════════════════════════════════════════════════════════════════

-- ── Profile: haengt an auth.users, haelt Anzeigename ──
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text,
  display_name  text,
  created_at    timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Profile sind fuer alle Angemeldeten lesbar (damit "angelegt von" anzeigbar ist)
create policy "profiles_select_authenticated"
  on public.profiles for select to authenticated using (true);

create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Profil bei Registrierung automatisch anlegen
create function public.handle_new_user()
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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at automatisch pflegen
create function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── Decoder-Features: ersetzt den bisherigen localStorage-Speicher ──
create table public.decoder_features (
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
  unique (type, position)
);

alter table public.decoder_features enable row level security;

create trigger decoder_features_touch
  before update on public.decoder_features
  for each row execute function public.touch_updated_at();

-- Alle Angemeldeten duerfen lesen und pflegen (gemeinsamer Wissensstand)
create policy "decoder_features_select"
  on public.decoder_features for select to authenticated using (true);

create policy "decoder_features_insert"
  on public.decoder_features for insert to authenticated
  with check (created_by = auth.uid());

create policy "decoder_features_update"
  on public.decoder_features for update to authenticated
  using (true) with check (updated_by = auth.uid());

create policy "decoder_features_delete"
  on public.decoder_features for delete to authenticated using (true);

-- ── Orakel: freie Wissensdatenbank (Frage/Antwort + Tags) ──
create table public.orakel_entries (
  id           uuid primary key default gen_random_uuid(),
  question     text not null check (char_length(question) between 1 and 300),
  answer       text not null check (char_length(answer) between 1 and 10000),
  tags         text[] not null default '{}',
  created_by   uuid references auth.users(id) on delete set null,
  updated_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table public.orakel_entries enable row level security;

create trigger orakel_entries_touch
  before update on public.orakel_entries
  for each row execute function public.touch_updated_at();

create policy "orakel_entries_select"
  on public.orakel_entries for select to authenticated using (true);

create policy "orakel_entries_insert"
  on public.orakel_entries for insert to authenticated
  with check (created_by = auth.uid());

create policy "orakel_entries_update"
  on public.orakel_entries for update to authenticated
  using (true) with check (updated_by = auth.uid());

create policy "orakel_entries_delete"
  on public.orakel_entries for delete to authenticated using (true);

-- Volltextsuche-Unterstuetzung fuer das Orakel
create index orakel_entries_search_idx on public.orakel_entries
  using gin (to_tsvector('german', question || ' ' || answer));
create index orakel_entries_tags_idx on public.orakel_entries using gin (tags);
create index decoder_features_lookup_idx on public.decoder_features (type, position);

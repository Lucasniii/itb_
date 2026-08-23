-- ── Rollenstruktur: profiles.role ──────────────────────────────
alter table public.profiles
  add column if not exists role text not null default 'user';

alter table public.profiles
  drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('user', 'admin'));

comment on column public.profiles.role is
  'user  = darf Eintraege einreichen (landen in der Freigabe),
   admin = darf freigeben/ablehnen und Rollen vergeben.';

-- Erster Admin (Projektverantwortlicher) – vor dem Guard-Trigger gesetzt.
update public.profiles set role = 'admin' where email = 'lucas.nigitsch@icloud.com';

-- ── Rollen-Lookup fuer RLS-Policies ────────────────────────────
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

comment on function public.is_admin() is
  'SECURITY DEFINER, damit Policies die Rolle lesen koennen, ohne rekursiv
   gegen die profiles-Policies zu laufen. Liest ausschliesslich die Zeile des
   angemeldeten Nutzers und gibt nur true/false zurueck – keine Inhalte.';

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ── Rollenwechsel absichern ────────────────────────────────────
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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

drop trigger if exists profiles_role_guard on public.profiles;
create trigger profiles_role_guard
  before update on public.profiles
  for each row execute function public.guard_profile_role();

-- Admins duerfen fremde Profile (=Rollen) aendern, alle anderen nur das eigene.
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

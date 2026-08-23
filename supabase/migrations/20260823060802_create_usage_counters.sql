-- ════════════════════════════════════════════════════════════════
--  Nutzungsstatistik – bewusst OHNE Personenbezug.
--  Gezaehlt wird nur "Ereignis X am Tag Y so-und-so-oft".
--  Kein Inhalt (keine Gerätestrings, Dateinamen, Kennzeichen),
--  keine user_id, keine IP.
-- ════════════════════════════════════════════════════════════════

create table public.usage_daily (
  day    date    not null default current_date,
  event  text    not null,
  count  integer not null default 0 check (count >= 0),
  primary key (day, event)
);

alter table public.usage_daily enable row level security;

-- Lesen nur fuer Angemeldete. Fuer anon gibt es KEINE Policy –
-- weder lesend noch schreibend. Geschrieben wird ausschliesslich
-- ueber log_usage() unten.
create policy "usage_daily_select_authenticated"
  on public.usage_daily for select to authenticated using (true);

-- Zaehl-Funktion: validiert das Ereignis und erhoeht den Tageszaehler
-- um genau 1. SECURITY DEFINER ist hier Absicht – nur so kann auch
-- nicht angemeldete Nutzung gezaehlt werden, ohne der anon-Rolle
-- direkten Schreibzugriff auf die Tabelle zu geben.
create function public.log_usage(p_event text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_event not in (
    'decoder_zconfig', 'decoder_zvalue', 'decoder_dataconfig',
    'decoder_checktmr', 'decoder_event',
    'km_pruefung', 'pto_erkennung'
  ) then
    return; -- unbekannte Ereignisse still verwerfen
  end if;

  insert into public.usage_daily (day, event, count)
  values (current_date, p_event, 1)
  on conflict (day, event)
  do update set count = public.usage_daily.count + 1;
end;
$$;

revoke execute on function public.log_usage(text) from public;
grant execute on function public.log_usage(text) to anon, authenticated;

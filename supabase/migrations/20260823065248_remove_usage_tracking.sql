-- Nutzungszaehlung wurde ersatzlos entfernt (Frontend und Datenbank).
-- Damit faellt auch der einzige Grund weg, der Rolle anon ueberhaupt
-- etwas zu erlauben: log_usage war die einzige anon-Berechtigung.
drop function if exists public.log_usage(text);
drop table if exists public.usage_daily;

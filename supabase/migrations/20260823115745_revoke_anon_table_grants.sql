-- Zweites Netz unter RLS: anon hatte durch die Supabase-Standardrechte noch
-- SELECT/INSERT/UPDATE/DELETE auf allen Tabellen. Geblockt wurde das bisher
-- ausschliesslich dadurch, dass keine Policy anon adressiert — ein einziges
-- versehentlich deaktiviertes RLS haette die Daten sofort weltweit geoeffnet.
-- Die App fragt abgemeldet ohnehin nie die Datenbank, es geht also nichts verloren.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

-- Neue Tabellen sollen anon gar nicht erst erreichen.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;

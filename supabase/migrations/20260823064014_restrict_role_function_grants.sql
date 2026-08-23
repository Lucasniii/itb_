-- Trigger-Funktionen brauchen keinen REST-Zugang; Trigger feuern unabhaengig
-- vom EXECUTE-Recht (das wird beim Anlegen des Triggers geprueft).
revoke all on function public.guard_review()       from public, anon, authenticated;
revoke all on function public.guard_profile_role() from public, anon, authenticated;

-- is_admin() wird nur aus Policies/Funktionen des angemeldeten Nutzers gebraucht.
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

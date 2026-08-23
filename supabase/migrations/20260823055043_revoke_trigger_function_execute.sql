-- Trigger-Funktionen sollen nicht ueber /rest/v1/rpc aufrufbar sein.
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.touch_updated_at() from anon, authenticated, public;

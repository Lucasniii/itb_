comment on function public.log_usage(text) is
'ABSICHTLICH SECURITY DEFINER und fuer anon freigegeben. Nur so kann Nutzung
 gezaehlt werden, die ohne Anmeldung stattfindet (KM-Pruefung, PTO-Erkennung),
 ohne der anon-Rolle Schreibrechte auf usage_daily zu geben.
 Angriffsflaeche ist eng: die Funktion nimmt einen einzigen Text entgegen,
 verwirft alles ausserhalb der Positivliste und kann ausschliesslich einen
 Tageszaehler um 1 erhoehen. Kein Lesen, kein Loeschen, keine Inhalte,
 kein Personenbezug. Zahlen koennen von aussen aufgeblaeht, aber nicht
 ausgelesen oder manipuliert werden; die Tabellengroesse ist durch das
 Tages-Bucket-Modell nach oben begrenzt.';

comment on table public.usage_daily is
'Aggregierte Nutzungszahlen pro Tag und Ereignis. Bewusst OHNE Personenbezug
 (keine user_id, keine IP) und ohne Inhalte. Schreibzugriff ausschliesslich
 ueber public.log_usage().';

# Migrationen

Abzug der Migrationen, die im Supabase-Projekt **ITB.BERICHTE**
(`jkxxgvhknswhbayvmmoc`, eu-central-1) tatsaechlich angewendet sind — exportiert aus
`supabase_migrations.schema_migrations`. Die Dateinamen entsprechen Version und Name
des jeweiligen Eintrags, der Inhalt ist zeichengenau derselbe.

**Das hier ist Dokumentation, kein Migrations-Werkzeug.** Es gibt in diesem Repo
keine Supabase-CLI, keinen Runner und keine Verknuepfung zum Projekt. Die Dateien
existieren, damit der Datenbankstand nachvollziehbar und im Ernstfall neu aufbaubar
ist — bis dahin lag er ausschliesslich in Supabase.

## Reihenfolge

| Version | Was passiert |
|---|---|
| `20260823055022` | Basisschema: `profiles`, `decoder_features`, `orakel_entries`, RLS, `handle_new_user`, `touch_updated_at` |
| `20260823055043` | EXECUTE auf den Trigger-Funktionen entzogen (kein REST-Zugang) |
| `20260823060802` | Nutzungszaehlung `usage_daily` + `log_usage()` — **spaeter wieder entfernt** |
| `20260823061127` | Kommentare, die den `anon`-Grant auf `log_usage()` begruenden |
| `20260823063149` | Rollen: `profiles.role`, `is_admin()`, `guard_profile_role()`, erster Admin |
| `20260823063248` | Freigabe-Workflow: `status`-Spalten, `guard_review()`, neue Policies, `approve_decoder_feature()`, partielle Unique-Indizes |
| `20260823064014` | EXECUTE auf `guard_review`/`guard_profile_role` entzogen, `is_admin()` nur fuer `authenticated` |
| `20260823065248` | Nutzungszaehlung ersatzlos geloescht — seitdem hat `anon` keinerlei Berechtigung mehr |

Die beiden Nutzungszaehlungs-Migrationen sind absichtlich mit abgelegt: sie erklaeren,
warum es die `log_usage()`-Funktion einmal gab und warum sie wieder verschwunden ist.

## Wenn sich am Schema etwas aendert

Neue Migration in Supabase anwenden und anschliessend hier als Datei nachziehen —
sonst driftet dieser Ordner vom echten Stand weg, und das waere schlimmer als gar
keine Dateien. Abgleich:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

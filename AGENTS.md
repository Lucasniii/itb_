# AGENTS.md

Einstieg für Coding-Agents in diesem Repo.

**Lies zuerst [CLAUDE.md](CLAUDE.md)** — dort steht die vollständige Anleitung:
Architektur, Supabase-Schema samt Rollen- und Freigabemodell, Aufbau der vier Tabs
und sämtliche Stilkonventionen. Diese Datei hier ist bewusst nur ein Verweis und
keine zweite Kopie: Es gab schon einmal zwei Fassungen, die auseinandergelaufen
sind, und die veraltete hat mehr geschadet als genutzt. Wer etwas an den
Konventionen ändert, ändert es in CLAUDE.md.

Vor einem neuen Feature zusätzlich [PROJECT_BRIEFING.md](PROJECT_BRIEFING.md) lesen —
Produktzweck, nicht verhandelbare Leitplanken, Roadmap und offene Produktfragen.

## Das Wichtigste in Kürze

Die gesamte App ist **eine Datei**: [index.html](index.html) (~2750 Zeilen, HTML + CSS +
JS inline). Kein Build-System, kein Paketmanager, kein Linter, keine Tests, keine CI.

```bash
python3 -m http.server 8765          # Vorschau: http://localhost:8765/index.html
# Inline-JS vor dem Commit auf Syntax prüfen:
python3 -c "import re; open('/tmp/s.js','w').write(re.search(r'<script>(.*)</script>\s*</body>', open('index.html').read(), re.S).group(1))"
node --check /tmp/s.js
```

Drei Punkte, an denen man sich am schnellsten vergreift:

1. **Die App ist öffentlich gehostet** (GitHub Pages, öffentliches Repo). Der
   Supabase-Key steht im Klartext in der Datei — das ist Absicht, weil der Schutz
   komplett in den RLS-Policies liegt und **keine Policy der Rolle `anon` etwas
   erlaubt**. Neue Tabellen: RLS an, ausschließlich `to authenticated`.
2. **Die Freigabepflicht steht in der Datenbank, nicht im Frontend** — Trigger
   `guard_review()` und `guard_profile_role()`. Nie darauf verlassen, dass die
   Oberfläche einen Button versteckt.
3. **XLSX-Inhalte verlassen den Browser nie.** Keine Analytics, kein Tracking,
   kein Upload von Tabelleninhalten.

Der angewendete Datenbankstand liegt als SQL unter
[supabase/migrations/](supabase/migrations/).

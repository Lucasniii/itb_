# PROJECT_BRIEFING.md

Produkt-Briefing für ITB.BERICHTE — ergänzt [CLAUDE.md](CLAUDE.md) (technische Konventionen) um Produktzweck, Leitplanken, Roadmap und offene Entscheidungen. Vor dem Start eines neuen Features hier nachlesen.

## Produktzweck

ITB.BERICHTE ist ein internes Werkzeug für die Auswertung von Telematik-/Fahrzeugdaten:

- **Decoder** — übersetzt rohe Gerätekonfigurationsstrings (`ZCONFIG`, `ZVALUE`, `DATACONFIG`, `CHECKTMR`, `EVENT`) von Telematik-Trackern in lesbare Bit-für-Bit-Beschreibungen, damit man ohne Handbuch nachvollziehen kann, was ein Gerät gerade tut oder tun soll.
- **KM-Pruefung** — prüft Fahrten-Exporte (XLSX) auf Kilometerstand-Fehler (Sprünge, eingefrorene Serien), um fehlerhafte oder manipulierte Fahrtenbuch-Daten zu erkennen.
- **PTO-Erkennung** — erkennt aus Detailberichten, welche Fahrzeuge Zapfwellen-/Zusatzaggregat-Nutzung (PTO) hatten.
- **Admin** — Wissens-Overlay, mit dem eigene Beschreibungstexte auf einzelne Decoder-Bits gelegt werden können, ohne die eingebauten Lookup-Tabellen zu verändern.

Zielgruppe: interne Nutzung durch den/die Entwickler:in bzw. wenige technisch versierte Kolleg:innen, kein Endkunden-Produkt. Alle vier Tabs sind eigenständige Werkzeuge, die dieselbe Datenbasis (Telematikgeräte/Fahrzeugberichte desselben Kontexts) aus unterschiedlichen Blickwinkeln bearbeiten.

## Nicht verhandelbare Leitplanken

Diese Punkte sind bewusste Architekturentscheidungen und dürfen nicht ohne ausdrückliche Rücksprache mit dem/der Projektverantwortlichen geändert werden:

1. **XLSX-Inhalte bleiben im Browser.** Fahrzeugberichte, Kennzeichen und Kilometerstände aus hochgeladenen Dateien werden ausschließlich lokal verarbeitet und niemals an einen Server geschickt. Keine Analytics, kein Tracking. (Die Supabase-Anbindung betrifft nur Decoder-Feature-Beschreibungen und das Orakel — siehe Punkt 2.)
2. **Die App ist öffentlich gehostet — Zugriffsschutz liegt komplett in den RLS-Policies.** Repo und GitHub-Pages-Seite (https://lucasniii.github.io/itb_/) sind öffentlich, der Supabase-Key steht damit im Klartext in [index.html](index.html). Das ist nur deshalb unbedenklich, weil **keine einzige Policy dem `anon`-Rolle etwas erlaubt**. Wer neue Tabellen anlegt: RLS aktivieren und ausschließlich `to authenticated`-Policies schreiben — sonst sind Kundennamen und Wissensinhalte sofort weltweit lesbar und beschreibbar.
3. **Freigabepflicht liegt in der Datenbank, nicht im Frontend.** Wer Wissensinhalte schreibt, tut das über Tabellen mit `status`-Spalte und `guard_review`-Trigger. Neue Inhaltstabellen bekommen denselben Trigger — Sichtbarkeit ohne Admin-Freigabe darf nie allein davon abhängen, dass die Oberfläche einen Button versteckt.
4. **Single-File-Architektur bleibt erhalten.** Kein Umbau auf ein Build-System, Framework oder Modulsystem, solange nicht ausdrücklich gewünscht — die Einfachheit (eine Datei öffnen/hosten reicht) ist ein Feature, kein technisches Schulden-Problem.
5. **Bestehende Decoder-Lookup-Tabellen (`ZC_DEFS`, `DATACONFIG_DEFS`, `EVENT_DEFS`, …) sind Fachdaten, keine beliebig editierbaren Konstanten.** Änderungen an Bit-Bedeutungen nur auf Basis verifizierter Gerätedokumentation, nicht aus Vermutung.
6. **Sprachkonvention einhalten**: UI und fachliche Kommentare bleiben Deutsch (mit ae/oe/ue-Ersatz), siehe [CLAUDE.md](CLAUDE.md).

## Priorisierte Roadmap

> Aktuell nur ein konkret vereinbarter Punkt. Weitere Prioritäten trägt der/die Projektverantwortliche hier nach — nicht spekulativ auffüllen.

1. **Orakel — neuer Wissensdatenbank-Tab** *(als Nächstes)*
   Ein fünfter Tab, der über die reinen Decoder-Bit-Beschreibungen (Admin-Tab) hinausgeht: ein durchsuchbarer Wissensspeicher für Troubleshooting-Erfahrungen, wiederkehrende Kundenfragen, Vorgehensweisen.
   **Die Datenbank-Seite steht bereits**: Tabelle `orakel_entries` (Frage, Antwort, Tags, Autor, Zeitstempel) inkl. RLS-Policies, Volltext-Index und Freigabe-Workflow (`status`, Trigger `guard_review`) ist angelegt und getestet — die Oberfläche muss den Status nur anzeigen, nicht selbst absichern. Es fehlt ausschließlich die Oberfläche: Tab, Formular, Liste, Suche/Tag-Filter — analog zum Admin-Tab aufgebaut und ebenfalls hinter dem Login.

## Erledigt

- **Supabase-Anbindung mit Mehrbenutzer-Login** *(23.08.2026)* — eigenes Projekt `ITB.BERICHTE` (`jkxxgvhknswhbayvmmoc`, eu-central-1); Admin-Feature-Beschreibungen liegen zentral statt in `localStorage` und sind für alle angemeldeten Kolleg:innen sichtbar. Login per E-Mail/Passwort. Einmalige Übernahme alter lokaler Features ist im Admin-Tab eingebaut.
- **Rollen & Freigabe-Workflow** *(23.08.2026)* — zwei Rollen in `profiles.role`: **user** darf einreichen und eigene, noch nicht freigegebene Einträge bearbeiten; **admin** gibt frei, lehnt ab und vergibt Rollen. Neue Registrierungen sind immer `user`. Eingereichtes erscheint erst nach Freigabe im Decoder; ein Änderungsvorschlag zu einer bereits freigegebenen Position verdrängt den freigegebenen Stand nicht, sondern liegt daneben, bis ein Admin ihn freigibt (dann ersetzt er ihn). Durchgesetzt wird das serverseitig durch Trigger (`guard_review`, `guard_profile_role`) und RLS — der Client kann den Status nicht setzen, auch nicht mit manipulierten Requests. Der letzte Admin kann sich die Rechte nicht selbst entziehen; Notausgang bleibt der Supabase-SQL-Editor. Gilt gleichermaßen für `orakel_entries`, damit der Orakel-Tab den Workflow schon fertig vorfindet.

  **Sichtbarkeit:** Der Admin-Reiter ist ausdrücklich nur für Admins sichtbar — Nicht-Admins sehen ihn gar nicht und reichen im aktuellen Stand also nichts ein; für sie ist die App ein reines Nachschlagewerk. Der Freigabe-Workflow bleibt trotzdem in der Datenbank aktiv, weil der geplante Orakel-Tab darüber laufen soll. Weil der Login bisher im Admin-Reiter steckte, gibt es jetzt einen **„Anmelden"-Knopf in der Kopfzeile**. Details in [CLAUDE.md](CLAUDE.md).

  Der Admin-Reiter hat zwei Unterreiter: **Feature anlegen** (Formular, Liste, offene Freigaben) und **Benutzer & Rollen**.
- **Nutzungsstatistik wieder entfernt** *(23.08.2026)* — die kurzzeitig eingebaute, bewusst personenlose Zählung („Ereignis X am Tag Y so-und-so-oft") ist auf Wunsch **vollständig zurückgebaut**: kein Panel im Admin-Tab, keine `logUsage()`-Aufrufe, Tabelle `usage_daily` und Funktion `log_usage()` gelöscht. Damit gibt es wieder **keine einzige Berechtigung für `anon`** — `log_usage` war die einzige. Falls Nutzungszahlen je wieder Thema werden: vorher klären, nicht stillschweigend nachrüsten.

## Offene Produktentscheidungen

Zum Orakel-Tab noch offen — die Datenbank ist bewusst so flexibel angelegt, dass alle Varianten möglich bleiben:

- **Inhaltsform**: Das Schema bildet Q&A ab (`question`/`answer`). Falls doch freie Artikel gewünscht sind, ließe sich `question` als Titel verwenden — vor dem Bau kurz klären.
- **Tags**: Spalte `tags text[]` existiert samt Index. Offen ist, ob die Oberfläche freie Tag-Eingabe bekommt oder eine feste Auswahlliste.
- **Verhältnis zu Admin-Tab**: Orakel ist als eigenständiger, nicht an Decoder-Bits gebundener Wissensspeicher gedacht (Admin bleibt strikt Bit-Beschreibungen). Falls sich das überschneiden soll, vorher klären.

## Wiederverwendbarer Task-Prompt

Vorlage, um eine neue Feature-Session in diesem Repo sauber zu starten (an den konkreten Task anpassen):

```
Kontext: ITB.BERICHTE, Single-File-App (index.html). Lies CLAUDE.md
(technische Konventionen: Farben, Typografie, Komponentenmuster,
JS-Stil) und PROJECT_BRIEFING.md (Produktzweck, Leitplanken, Roadmap)
bevor du startest.

Aufgabe: <konkrete Aufgabe hier>

Vorgaben:
- Halte dich an die bestehenden Styles/Patterns aus CLAUDE.md
  (keine neuen Farben/Fonts/Border-Radien erfinden).
- Keine neuen externen Abhängigkeiten außer bei ausdrücklicher
  Rücksprache.
- Keine Server-/Backend-Kommunikation einführen (siehe Leitplanken
  in PROJECT_BRIEFING.md).
- Bei offenen Produktentscheidungen (siehe PROJECT_BRIEFING.md)
  erst nachfragen statt anzunehmen.
- Nach Umsetzung: `node --check` auf das extrahierte inline JS
  laufen lassen (siehe CLAUDE.md „Commands").
```

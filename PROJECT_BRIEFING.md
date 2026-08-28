# PROJECT_BRIEFING.md

Produkt-Briefing für ITB.BERICHTE — ergänzt [CLAUDE.md](CLAUDE.md) (technische Konventionen) um Produktzweck, Leitplanken, Roadmap und offene Entscheidungen. Vor dem Start eines neuen Features hier nachlesen.

## Produktzweck

ITB.BERICHTE ist ein internes Werkzeug für die Auswertung von Telematik-/Fahrzeugdaten:

- **Decoder** — übersetzt rohe Gerätekonfigurationsstrings (`ZCONFIG`, `ZVALUE`, `DATACONFIG`, `CHECKTMR`, `EVENT`) von Telematik-Trackern in lesbare Bit-für-Bit-Beschreibungen, damit man ohne Handbuch nachvollziehen kann, was ein Gerät gerade tut oder tun soll.
- **KM-Pruefung** — prüft Fahrten-Exporte (XLSX) auf Kilometerstand-Fehler (Sprünge, eingefrorene Serien), um fehlerhafte oder manipulierte Fahrtenbuch-Daten zu erkennen.
- **PTO-Erkennung** — erkennt aus Detailberichten, welche Fahrzeuge Zapfwellen-/Zusatzaggregat-Nutzung (PTO) hatten.
- **Admin** — Wissens-Overlay, mit dem eigene Beschreibungstexte auf einzelne Decoder-Bits gelegt werden können, ohne die eingebauten Lookup-Tabellen zu verändern.
- **Import** (Unterreiter im Admin) — macht aus einer im Browser gespeicherten Hersteller-Anleitung (`.htm` plus `_files`-Ordner) eine durchgehende PDF zum Herunterladen.

Zielgruppe: interne Nutzung durch den/die Entwickler:in bzw. wenige technisch versierte Kolleg:innen, kein Endkunden-Produkt. Alle vier Tabs sind eigenständige Werkzeuge, die dieselbe Datenbasis (Telematikgeräte/Fahrzeugberichte desselben Kontexts) aus unterschiedlichen Blickwinkeln bearbeiten.

## Nicht verhandelbare Leitplanken

Diese Punkte sind bewusste Architekturentscheidungen und dürfen nicht ohne ausdrückliche Rücksprache mit dem/der Projektverantwortlichen geändert werden:

1. **Jeder angemeldete Nutzer gilt als vertrauenswürdig.** Das gesamte RLS-Modell steht auf dieser Annahme. Ob sich jemand selbst registrieren kann und ob Adressen automatisch bestätigt werden, entscheidet eine Einstellung im Supabase-Dashboard — nicht der Code. Wer sie öffnet, öffnet damit die zentralen Decoder-Beschreibungen samt Kundennamen und alle Kolleg:innen-Adressen für jeden, der die öffentliche URL kennt.
2. **XLSX-Inhalte bleiben im Browser.** Fahrzeugberichte, Kennzeichen und Kilometerstände aus hochgeladenen Dateien werden ausschließlich lokal verarbeitet und niemals an einen Server geschickt. Keine Analytics, kein Tracking. Die Supabase-Anbindung betrifft nur Decoder-Feature-Beschreibungen.
3. **Die App ist öffentlich gehostet — Zugriffsschutz liegt komplett in den RLS-Policies.** Repo und GitHub-Pages-Seite (https://lucasniii.github.io/itb_/) sind öffentlich, der Supabase-Key steht damit im Klartext in [index.html](index.html). Das ist nur deshalb unbedenklich, weil **keine einzige Policy dem `anon`-Rolle etwas erlaubt**. Wer neue Tabellen anlegt: RLS aktivieren und ausschließlich `to authenticated`-Policies schreiben — sonst sind Kundennamen und Wissensinhalte sofort weltweit lesbar und beschreibbar.
4. **Freigabepflicht liegt in der Datenbank, nicht im Frontend.** Wer Wissensinhalte schreibt, tut das über Tabellen mit `status`-Spalte und `guard_review`-Trigger. Neue Inhaltstabellen bekommen denselben Trigger — Sichtbarkeit ohne Admin-Freigabe darf nie allein davon abhängen, dass die Oberfläche einen Button versteckt.
5. **Single-File-Architektur bleibt erhalten.** Kein Umbau auf ein Build-System, Framework oder Modulsystem, solange nicht ausdrücklich gewünscht — die Einfachheit (eine Datei öffnen/hosten reicht) ist ein Feature, kein technisches Schulden-Problem.
6. **Bestehende Decoder-Lookup-Tabellen (`ZC_DEFS`, `DATACONFIG_DEFS`, `EVENT_DEFS`, …) sind Fachdaten, keine beliebig editierbaren Konstanten.** Änderungen an Bit-Bedeutungen nur auf Basis verifizierter Gerätedokumentation, nicht aus Vermutung.
7. **Sprachkonvention einhalten**: UI und fachliche Kommentare bleiben Deutsch (mit ae/oe/ue-Ersatz), siehe [CLAUDE.md](CLAUDE.md).

## Priorisierte Roadmap

> Aktuell ist kein weiterer Punkt konkret priorisiert. Weitere Prioritäten trägt der/die Projektverantwortliche hier nach — nicht spekulativ auffüllen.

## Erledigt

- **Import-Unterreiter: Web-Anleitung als PDF** *(28.08.2026)* — aus der Schwester-App [itb-wissensdatenbank](https://github.com/Lucasniii/itb-wissensdatenbank) übernommen. Man legt den Ordner ab, in dem eine mit „Seite speichern unter“ abgelegte Hersteller-Anleitung liegt (genau eine `.htm`-Datei plus der gleichnamige `_files`-Ordner), oder wählt ihn über den Knopf; daraus wird eine durchgehende A4-PDF gebaut und sofort heruntergeladen. Ablegen geht sowohl mit dem Elternordner als auch mit `.htm` und `_files`-Ordner nebeneinander. Die ausführliche Erklärung hängt am `i` neben der Überschrift statt dauerhaft im Panel zu stehen.

  **Unterschied zur Vorlage:** dort landet das Ergebnis als Entwurf in der Wissensdatenbank samt KI-Suchindex. Diese App hat keine Wissensdatenbank — hier wird die PDF nur erzeugt und heruntergeladen. Die Dateien verlassen den Browser nicht, es geht nichts an Supabase (Leitplanke 2).

  **Zwei neue CDN-Abhängigkeiten** (beide mit SRI-Hash und `crossorigin`, siehe [CLAUDE.md](CLAUDE.md)): `html2canvas` 1.4.1 rastert die aufbereitete Seite, `jspdf` 4.2.1 schneidet sie in A4-Seiten. Ohne die beiden ist das Feature nicht baubar; jsPDF ist bewusst 4.x statt der 2.5.1 der Vorlage, weil ältere Versionen bekannte Schwachstellen haben — dieselbe Überlegung wie beim SheetJS-Wechsel.

  Sicherheit: aus der fremden Seite wird nichts ausgeführt. `script`, `iframe`, `form`, alle `on*`-Attribute und alle `href`s werden vor dem Rendern entfernt, aufgebaut wird in einem eigenen Off-Screen-`srcdoc`-iframe.

- **Supabase-Anbindung mit Mehrbenutzer-Login** *(23.08.2026)* — eigenes Projekt `ITB.BERICHTE` (`jkxxgvhknswhbayvmmoc`, eu-central-1); Admin-Feature-Beschreibungen liegen zentral statt in `localStorage` und sind für alle angemeldeten Kolleg:innen sichtbar. Login per E-Mail/Passwort. Einmalige Übernahme alter lokaler Features ist im Admin-Tab eingebaut.
- **Rollen & Freigabe-Workflow** *(23.08.2026)* — zwei Rollen in `profiles.role`: **user** darf einreichen und eigene, noch nicht freigegebene Decoder-Beschreibungen bearbeiten; **admin** gibt frei, lehnt ab und vergibt Rollen. Neue Registrierungen sind immer `user`. Eingereichtes erscheint erst nach Freigabe im Decoder; ein Änderungsvorschlag zu einer bereits freigegebenen Position verdrängt den freigegebenen Stand nicht, sondern liegt daneben, bis ein Admin ihn freigibt (dann ersetzt er ihn). Durchgesetzt wird das serverseitig durch Trigger (`guard_review`, `guard_profile_role`) und RLS — der Client kann den Status nicht setzen, auch nicht mit manipulierten Requests. Der letzte Admin kann sich die Rechte nicht selbst entziehen; Notausgang bleibt der Supabase-SQL-Editor.

  **Sichtbarkeit:** Der Admin-Reiter ist ausdrücklich nur für Admins sichtbar — Nicht-Admins sehen ihn gar nicht; für sie ist die App ein reines Nachschlagewerk. Weil der Login im Admin-Reiter steckt, gibt es einen **„Anmelden"-Knopf in der Kopfzeile**. Details in [CLAUDE.md](CLAUDE.md).

  Der Admin-Reiter hat zwei Unterreiter: **Feature anlegen** (Formular, Liste, offene Freigaben) und **Benutzer & Rollen**.
- **Sicherheits-Nachzug** *(23.08.2026)* — drei Punkte aus einer Stichprobenprüfung behoben: (1) Kennzeichen, Datums-/Zeitwerte und Dateinamen aus hochgeladenen XLSX gingen ungeescaped ins DOM und hätten über eine präparierte Datei Skript ausführen können — laufen jetzt alle durch `zcEsc()`; (2) die drei CDN-Skripte haben SRI-Hashes und `crossorigin` bekommen, SheetJS ist von 0.18.5 (bekannte Schwachstellen, npm/cdnjs gehen nicht höher) auf 0.20.3 vom Hersteller-CDN gewechselt — die von der App genutzten APIs sind vorher in Node gegen beide Versionen geprüft worden und liefern identische Ergebnisse; (3) `anon` hatte auf SQL-Ebene noch die Supabase-Standardrechte, die nur durch RLS ins Leere liefen — jetzt zusätzlich entzogen, inklusive Default-Privilegien für künftige Tabellen. **Offen und nicht durch Code lösbar:** die Registrierung wird im Supabase-Dashboard geregelt (siehe Leitplanke 1).
- **Nutzungsstatistik wieder entfernt** *(23.08.2026)* — die kurzzeitig eingebaute, bewusst personenlose Zählung („Ereignis X am Tag Y so-und-so-oft") ist auf Wunsch **vollständig zurückgebaut**: kein Panel im Admin-Tab, keine `logUsage()`-Aufrufe, Tabelle `usage_daily` und Funktion `log_usage()` gelöscht. Damit gibt es wieder **keine einzige Berechtigung für `anon`** — `log_usage` war die einzige. Falls Nutzungszahlen je wieder Thema werden: vorher klären, nicht stillschweigend nachrüsten.

## Offene Produktentscheidungen

Aktuell sind keine offenen Produktentscheidungen dokumentiert.

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

# PROJECT_BRIEFING.md

Produkt-Briefing für ITB.BERICHTE — ergänzt [DEVELOPMENT.md](DEVELOPMENT.md) (technische Konventionen) um Produktzweck, Leitplanken, Roadmap und offene Entscheidungen. Vor dem Start eines neuen Features hier nachlesen.

## Produktzweck

ITB.BERICHTE ist ein internes Werkzeug für die Auswertung von Telematik-/Fahrzeugdaten:

- **Decoder** — übersetzt rohe Gerätekonfigurationsstrings (`ZCONFIG`, `ZVALUE`, `DATACONFIG`, `CHECKTMR`, `EVENT`) von Telematik-Trackern in lesbare Bit-für-Bit-Beschreibungen, damit man ohne Handbuch nachvollziehen kann, was ein Gerät gerade tut oder tun soll. Ein eigener Reiter daneben ist die **CAN Verfuegbarkeit**: Modell und Baujahr eingeben (z. B. „MAN TGX 2024") und ablesen, welche CAN-Werte das S10-Modul bei diesem Fahrzeug überhaupt liefern kann — die Frage, die vor jedem Einbau ansteht.
- **KM-Pruefung** — prüft Fahrten-Exporte (XLSX) auf Kilometerstand-Fehler (Sprünge, eingefrorene Serien), um fehlerhafte oder manipulierte Fahrtenbuch-Daten zu erkennen.
- **PTO-Erkennung** — erkennt aus Detailberichten, welche Fahrzeuge Zapfwellen-/Zusatzaggregat-Nutzung (PTO) hatten.
- **Seriennummern** — filtert einen CSV-Geräteexport über beliebig viele Bedingungen (Nummernkreis, Firmware-Stand, Kunde, Modell …) und gibt die Seriennummern der übrig gebliebenen Fahrzeuge als eine mit `|` getrennte Liste aus, wie sie die Nachbarsysteme zum Einfügen erwarten.
- **Admin** — Wissens-Overlay, mit dem eigene Beschreibungstexte auf einzelne Decoder-Bits gelegt werden können, ohne die eingebauten Lookup-Tabellen zu verändern.
- **Import** (Unterreiter im Admin) — macht aus einer im Browser gespeicherten Hersteller-Anleitung (`.htm` plus `_files`-Ordner) eine durchgehende PDF zum Herunterladen.

Zielgruppe: interne Nutzung durch den/die Entwickler:in bzw. wenige technisch versierte Kolleg:innen, kein Endkunden-Produkt. Alle Reiter sind eigenständige Werkzeuge, die dieselbe Datenbasis (Telematikgeräte/Fahrzeugberichte desselben Kontexts) aus unterschiedlichen Blickwinkeln bearbeiten.

## Nicht verhandelbare Leitplanken

Diese Punkte sind bewusste Architekturentscheidungen und dürfen nicht ohne ausdrückliche Rücksprache mit dem/der Projektverantwortlichen geändert werden:

1. **Jeder angemeldete Nutzer gilt als vertrauenswürdig.** Das gesamte RLS-Modell steht auf dieser Annahme. Ob sich jemand selbst registrieren kann und ob Adressen automatisch bestätigt werden, entscheidet eine Einstellung im Supabase-Dashboard — nicht der Code. Wer sie öffnet, öffnet damit die zentralen Decoder-Beschreibungen samt Kundennamen und alle Kolleg:innen-Adressen für jeden, der die öffentliche URL kennt.
2. **XLSX-Inhalte bleiben im Browser.** Fahrzeugberichte, Kennzeichen und Kilometerstände aus hochgeladenen Dateien werden ausschließlich lokal verarbeitet und niemals an einen Server geschickt. Keine Analytics, kein Tracking. Die Supabase-Anbindung betrifft nur Decoder-Feature-Beschreibungen.
3. **Die App ist öffentlich gehostet — Zugriffsschutz liegt komplett in den RLS-Policies.** Repo und GitHub-Pages-Seite (https://lucasniii.github.io/itb_/) sind öffentlich, der Supabase-Key steht damit im Klartext in [index.html](index.html). Das ist nur deshalb unbedenklich, weil **keine einzige Policy dem `anon`-Rolle etwas erlaubt**. Wer neue Tabellen anlegt: RLS aktivieren und ausschließlich `to authenticated`-Policies schreiben — sonst sind Kundennamen und Wissensinhalte sofort weltweit lesbar und beschreibbar.
4. **Freigabepflicht liegt in der Datenbank, nicht im Frontend.** Wer Wissensinhalte schreibt, tut das über Tabellen mit `status`-Spalte und `guard_review`-Trigger. Neue Inhaltstabellen bekommen denselben Trigger — Sichtbarkeit ohne Admin-Freigabe darf nie allein davon abhängen, dass die Oberfläche einen Button versteckt.
5. **Single-File-Architektur bleibt erhalten.** Kein Umbau auf ein Build-System, Framework oder Modulsystem, solange nicht ausdrücklich gewünscht — die Einfachheit (eine Datei öffnen/hosten reicht) ist ein Feature, kein technisches Schulden-Problem.
6. **Bestehende Decoder-Lookup-Tabellen (`ZC_DEFS`, `DATACONFIG_DEFS`, `EVENT_DEFS`, …) sind Fachdaten, keine beliebig editierbaren Konstanten.** Änderungen an Bit-Bedeutungen nur auf Basis verifizierter Gerätedokumentation, nicht aus Vermutung.
7. **Sprachkonvention einhalten**: UI und fachliche Kommentare bleiben Deutsch (mit ae/oe/ue-Ersatz), siehe [DEVELOPMENT.md](DEVELOPMENT.md).

## Priorisierte Roadmap

> Aktuell ist kein weiterer Punkt konkret priorisiert. Weitere Prioritäten trägt der/die Projektverantwortliche hier nach — nicht spekulativ auffüllen.

## Erledigt

- **Reiterleiste neu geordnet, CAN Verfuegbarkeit als eigener Reiter** *(09.09.2026)* — Reihenfolge ist jetzt **Decoder · Seriennummern · CAN Verfuegbarkeit · KM-Pruefung · PTO-Erkennung · Admin**. Die CAN-Suche lag bisher als zweiter Bereich im Decoder-Reiter hinter einer `.zc-fbtn`-Umschaltzeile; sie ist ein vollwertiges Werkzeug und war dort schlicht schwer zu finden. `vehSetPane()` samt `#zc-pane-dec`/`#zc-pane-veh` ist ersatzlos weg — was beim Öffnen passieren muss (Suchfeld fokussieren, Liste aufbauen) erledigt jetzt `showView()`, so wie es das für den Admin-Reiter schon tat.

  Sechs Reiter passen auf schmalen Schirmen nicht mehr in eine Zeile, deshalb bricht die Leiste dort um (`flex-wrap`) und die Reiter bekommen engere Polsterung — vorher hätte die ganze Seite horizontal gescrollt.

- **Seriennummern-Reiter** *(09.09.2026)* — ein CSV-Geräteexport wird abgelegt, beliebig viele Bedingungen grenzen ihn ein, und unten steht die fertige, mit `|` getrennte Seriennummernliste zum Kopieren (`151759|258941|258943`). Jede Bedingung ist eine Zeile aus *Spalte* (oder „Alle Spalten"), *Operator* (`enthaelt`, `enthaelt nicht`, `Zahlenbereich` — bewusst nur diese drei) und Wert; die Bedingungen sind UND-verknüpft, mehrere Werte innerhalb einer Bedingung ODER-verknüpft. Damit ist der typische Fall „Nummernkreis 150000–170000 **und** Firmware `Jul 31 2026` oder `Jul  5 2021`" eine einzige Ansicht. Ausgabespalte und Trennzeichen sind einstellbar, doppelte Nummern fallen immer weg, darunter liegt eine Trefferliste als Tabelle.

  **Die Firmware-Spalte wird aufgeteilt.** `Jul 10 2025 18:05:34 | C:2.3.12 b [0] | T:2.1.7.9` sind drei Stände in einem Feld: die Geräte-Firmware (die über ihr Build-Datum benannt wird), die CAN-Firmware hinter `C:` und die Tachoversion hinter `T:`. Der Reiter zieht das beim Einlesen auseinander: CAN und Tacho werden zu den eigenen Spalten *Firmware - CAN* und *Firmware - Tacho* direkt hinter dem Original, und **die Firmware-Spalte selbst behält nur das Build-Datum** (`Jul 10 2025 18:05:34 | C:… | T:…` → `Jul 10 2025`). Damit filtert jeder Stand für sich: „alle mit CAN-Stand 2.3.9 e", „Tachoversion 2.1.7", „Firmware Jul 31 2026".

  Warum gekürzt wird: Uhrzeit und die beiden hinteren Stände zersplittern eine Firmware sonst über viele Werte — **186 verschiedene Zeichenketten gegenüber 52 Datumswerten**. Erst dadurch ist die Vorschlagsliste auf dieser Spalte überhaupt brauchbar.

  **Das Format wird erzwungen, nicht nur gesucht:** in der Spalte steht am Ende ein Datum `Mon T JJJJ` oder gar nichts. Werte, die nicht so beginnen (`Level`, atrack `Rev.1.10 Build.260600` — 15 Zeilen), sind in diesem Sinn keine Firmware und fallen weg, statt als Fremdtext in einer Datumsspalte zu stehen; diese Geräte bleiben über *Device Typ* und *Modell* auffindbar.

  **Die Vorschlagslisten stehen sortiert, der aktuellste Stand oben:** Build-Daten chronologisch (neuestes zuerst), CAN- und Tacho-Versionen numerisch (höchste zuerst — `2.3.12` über `2.3.9`, was ein Textvergleich falsch herum sortieren würde, und `3.0.24 h` über `3.0.24 g`). Nach Häufigkeit zu sortieren sagt bei Firmware-Ständen nichts aus; die Frage ist immer „was ist der neueste/höchste Stand". Die Sortierung hängt an der Art der Werte, nicht an einem festen Spaltennamen — alle anderen Spalten bleiben nach Häufigkeit sortiert, deutsche Datumsangaben (`27.06.2022 10:23`) ausdrücklich eingeschlossen, weil sie sonst nach Kalendertag statt chronologisch stünden.

  Das Kürzen ist die **einzige** Stelle, an der der Reiter einen gelieferten Zellwert verändert. Angezeigt wird das nicht: die Statusleiste meldet nur noch Fehler und die Kopier-Bestätigung, ein grünes Band nach jedem Laden war bei täglicher Nutzung nur Rauschen (Zeilenzahl steht in den Kacheln, Dateiname in der Ablagefläche).

  **Kein neuer Abhängigkeitsbedarf:** die CSV wird von einem eigenen Parser gelesen, nicht von SheetJS — Trennzeichen wird aus der Kopfzeile geraten, BOM, gequotete Felder mit verdoppelten Quotes (der Export enthält JSON), Trennzeichen und Umbrüche im Feld sowie CRLF/LF sind abgedeckt; UTF-8 mit Rückfall auf windows-1252. Wie bei den XLSX-Reitern **verlässt die Datei den Browser nicht** (Leitplanke 2), es geht nichts an Supabase.

  Ein Detail, das aus den echten Daten kommt: die Firmware-Spalte füllt einstellige Tage mit einem zweiten Leerzeichen auf (`Jul  5 2021`). Verglichen wird deshalb mit zusammengefassten Leerzeichen, damit ein getipptes `Jul 5 2021` trifft.

- **CAN Verfuegbarkeit im Decoder-Reiter** *(03.09.2026)* — Freitextsuche über 919 Modelle: „MAN TGX 2024" führt zu den Generationen, deren Baujahresbereich das Jahr enthält; abweichende Generationen stehen darunter unter „Andere Generationen". Die Detailansicht zeigt gruppiert, welche der 64 CAN-Werte das Modell liefert (`JA` / `BEDINGT` bei kontaktloser Anbindung), dazu die digitalen Zustandsanzeigen und die Fußnoten der Vorlage. Standardmäßig sind alle Parameter zu sehen ("Alle Parameter"), auf Wunsch nur die tatsächlich verfügbaren ("Nur verfuegbare"); ein Suchfeld filtert zusätzlich nach Parameternamen (deutsch oder englisch).

  **Datenherkunft:** die drei Albatross-Tabellen zum S10-CAN-Modul (Firmware 3.0.28, Stand 27.08.2026). Die On-Road-Tabelle ist die Obermenge — alle 125 Lkw-/Bus- und alle 98 E-Auto-Zeilen stehen dort zeichengleich drin —, deshalb liegt nur **eine** Liste in `VEH_DB`; das letzte Feld je Zeile vermerkt nur, in welcher Spezialtabelle ein Modell zusätzlich geführt wird. Die Tabellen sind Rastergrafik-artig gesetzt (Häkchen in einer Symbolschrift ohne Spaltenbezug im Text), die Zuordnung Häkchen → Spalte kommt daher aus den x-Koordinaten: 31.236 Markierungen, größte Abweichung von einer Spaltenmitte 0,20 pt bei 6,24 pt halber Spaltenbreite, und die Summe je Symbolart stimmt mit den Zeilen überein. `VEH_DB` ist damit **Fachdatum wie `ZC_DEFS`** (Leitplanke 6) — Änderungen nur gegen eine neue Herstellertabelle, nicht per Hand.

  Umgesetzt ohne neue Abhängigkeit und ohne Server. Sie lag zunächst als zweiter Bereich im Decoder-Reiter, umgeschaltet über eine `.zc-fbtn`-Zeile; seit dem Umbau der Reiterleiste (09.09.2026) ist sie ein **eigener Reiter** — der versteckte Umschalter war für ein Werkzeug dieser Größe die falsche Ablage.

- **Import-Unterreiter: Web-Anleitung als PDF** *(28.08.2026)* — aus der Schwester-App [itb-wissensdatenbank](https://github.com/Lucasniii/itb-wissensdatenbank) übernommen. Man legt den Ordner ab, in dem eine mit „Seite speichern unter“ abgelegte Hersteller-Anleitung liegt (genau eine `.htm`-Datei plus der gleichnamige `_files`-Ordner), oder wählt ihn über den Knopf; daraus wird eine durchgehende A4-PDF gebaut und sofort heruntergeladen. Ablegen geht sowohl mit dem Elternordner als auch mit `.htm` und `_files`-Ordner nebeneinander. Die ausführliche Erklärung hängt am `i` neben der Überschrift statt dauerhaft im Panel zu stehen.

  **Unterschied zur Vorlage:** dort landet das Ergebnis als Entwurf in der Wissensdatenbank samt KI-Suchindex. Diese App hat keine Wissensdatenbank — hier wird die PDF nur erzeugt und heruntergeladen. Die Dateien verlassen den Browser nicht, es geht nichts an Supabase (Leitplanke 2).

  **Zwei neue CDN-Abhängigkeiten** (beide mit SRI-Hash und `crossorigin`, siehe [DEVELOPMENT.md](DEVELOPMENT.md)): `html2canvas` 1.4.1 rastert die aufbereitete Seite, `jspdf` 4.2.1 schneidet sie in A4-Seiten. Ohne die beiden ist das Feature nicht baubar; jsPDF ist bewusst 4.x statt der 2.5.1 der Vorlage, weil ältere Versionen bekannte Schwachstellen haben — dieselbe Überlegung wie beim SheetJS-Wechsel.

  Sicherheit: aus der fremden Seite wird nichts ausgeführt. `script`, `iframe`, `form`, alle `on*`-Attribute und alle `href`s werden vor dem Rendern entfernt, aufgebaut wird in einem eigenen Off-Screen-`srcdoc`-iframe.

- **Supabase-Anbindung mit Mehrbenutzer-Login** *(23.08.2026)* — eigenes Projekt `ITB.BERICHTE` (`jkxxgvhknswhbayvmmoc`, eu-central-1); Admin-Feature-Beschreibungen liegen zentral statt in `localStorage` und sind für alle angemeldeten Kolleg:innen sichtbar. Login per E-Mail/Passwort. Einmalige Übernahme alter lokaler Features ist im Admin-Tab eingebaut.
- **Rollen & Freigabe-Workflow** *(23.08.2026)* — zwei Rollen in `profiles.role`: **user** darf einreichen und eigene, noch nicht freigegebene Decoder-Beschreibungen bearbeiten; **admin** gibt frei, lehnt ab und vergibt Rollen. Neue Registrierungen sind immer `user`. Eingereichtes erscheint erst nach Freigabe im Decoder; ein Änderungsvorschlag zu einer bereits freigegebenen Position verdrängt den freigegebenen Stand nicht, sondern liegt daneben, bis ein Admin ihn freigibt (dann ersetzt er ihn). Durchgesetzt wird das serverseitig durch Trigger (`guard_review`, `guard_profile_role`) und RLS — der Client kann den Status nicht setzen, auch nicht mit manipulierten Requests. Der letzte Admin kann sich die Rechte nicht selbst entziehen; Notausgang bleibt der Supabase-SQL-Editor.

  **Sichtbarkeit:** Der Admin-Reiter ist ausdrücklich nur für Admins sichtbar — Nicht-Admins sehen ihn gar nicht; für sie ist die App ein reines Nachschlagewerk. Weil der Login im Admin-Reiter steckt, gibt es einen **„Anmelden"-Knopf in der Kopfzeile**. Details in [DEVELOPMENT.md](DEVELOPMENT.md).

  Der Admin-Reiter hatte damals zwei Unterreiter: **Feature anlegen** (Formular, Liste, offene Freigaben) und **Benutzer & Rollen**. Seit dem Import-Feature sind es drei, in der Reihenfolge **Feature anlegen**, **Import**, **Benutzer & Rollen**.
- **Sicherheits-Nachzug** *(23.08.2026)* — drei Punkte aus einer Stichprobenprüfung behoben: (1) Kennzeichen, Datums-/Zeitwerte und Dateinamen aus hochgeladenen XLSX gingen ungeescaped ins DOM und hätten über eine präparierte Datei Skript ausführen können — laufen jetzt alle durch `zcEsc()`; (2) die drei CDN-Skripte haben SRI-Hashes und `crossorigin` bekommen, SheetJS ist von 0.18.5 (bekannte Schwachstellen, npm/cdnjs gehen nicht höher) auf 0.20.3 vom Hersteller-CDN gewechselt — die von der App genutzten APIs sind vorher in Node gegen beide Versionen geprüft worden und liefern identische Ergebnisse; (3) `anon` hatte auf SQL-Ebene noch die Supabase-Standardrechte, die nur durch RLS ins Leere liefen — jetzt zusätzlich entzogen, inklusive Default-Privilegien für künftige Tabellen. **Offen und nicht durch Code lösbar:** die Registrierung wird im Supabase-Dashboard geregelt (siehe Leitplanke 1).
- **Nutzungsstatistik wieder entfernt** *(23.08.2026)* — die kurzzeitig eingebaute, bewusst personenlose Zählung („Ereignis X am Tag Y so-und-so-oft") ist auf Wunsch **vollständig zurückgebaut**: kein Panel im Admin-Tab, keine `logUsage()`-Aufrufe, Tabelle `usage_daily` und Funktion `log_usage()` gelöscht. Damit gibt es wieder **keine einzige Berechtigung für `anon`** — `log_usage` war die einzige. Falls Nutzungszahlen je wieder Thema werden: vorher klären, nicht stillschweigend nachrüsten.

## Offene Produktentscheidungen

Aktuell sind keine offenen Produktentscheidungen dokumentiert.

## Wiederverwendbarer Task-Prompt

Vorlage, um eine neue Feature-Session in diesem Repo sauber zu starten (an den konkreten Task anpassen):

```
Kontext: ITB.BERICHTE, Single-File-App (index.html). Lies DEVELOPMENT.md
(technische Konventionen: Farben, Typografie, Komponentenmuster,
JS-Stil) und PROJECT_BRIEFING.md (Produktzweck, Leitplanken, Roadmap)
bevor du startest.

Aufgabe: <konkrete Aufgabe hier>

Vorgaben:
- Halte dich an die bestehenden Styles/Patterns aus DEVELOPMENT.md
  (keine neuen Farben/Fonts/Border-Radien erfinden).
- Keine neuen externen Abhängigkeiten außer bei ausdrücklicher
  Rücksprache.
- Keine Server-/Backend-Kommunikation einführen (siehe Leitplanken
  in PROJECT_BRIEFING.md).
- Bei offenen Produktentscheidungen (siehe PROJECT_BRIEFING.md)
  erst nachfragen statt anzunehmen.
- Nach Umsetzung: `node --check` auf das extrahierte inline JS
  laufen lassen (siehe DEVELOPMENT.md „Commands").
```

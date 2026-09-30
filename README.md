# ITB Multitool

Internes Browser-Tool für Support und Technik zur Auswertung, Prüfung und Aufbereitung von Fahrzeug- und Telematikdaten.

## Funktionen

- **Decoder** für Konfigurationswerte wie ZCONFIG, ZVALUE, DATACONFIG, CHECKTMR und EVENT
- **CAN Verfügbarkeit** zur Suche nach unterstützten Fahrzeug- und CAN-Parametern
- **KM-Prüfung** zur Plausibilitätskontrolle von Fahrtenberichten
- **PTO-Erkennung** für Nebenantrieb-/Input-Auswertungen
- **Seriennummern** zum Filtern und Aufbereiten von Geräteexporten
- **Admin-Bereich** für freigegebene Decoder-Beschreibungen und Benutzerrollen
- **Import** zur lokalen Aufbereitung von Hersteller-Anleitungen als PDF

## Technik

Die Anwendung ist bewusst schlank aufgebaut:

- statische Single-Page-Anwendung in `index.html`
- HTML, CSS und JavaScript ohne Framework
- Supabase für Anmeldung, Rollen und freigegebene Decoder-Inhalte
- lokale Verarbeitung hochgeladener XLSX-, CSV- und Importdateien direkt im Browser

## Datenschutz und Verarbeitung

Dateien für KM-Prüfung, Seriennummern, PTO-Erkennung und Import werden lokal im Browser verarbeitet. Inhalte dieser Dateien werden nicht an Supabase übertragen.

GoatCounter erfasst Seitenaufrufe unter `https://lucasni.goatcounter.com`. Die Integration verwendet einen festen Seitennamen, deaktiviert Klick-Ereignisse und übermittelt keine Formulareingaben oder Dateiinhalte. Auf der Website ist ein aufklappbarer Datenschutzhinweis vorhanden.

## Start

Für eine lokale Vorschau kann das Repository direkt über einen einfachen Webserver gestartet werden:

```bash
python3 -m http.server 8765
```

Danach ist die Anwendung unter `http://localhost:8765/index.html` erreichbar.

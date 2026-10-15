# Werkstatt für iPhone

Native SwiftUI-App für iPhone ab iOS 17. Der Prototyp läuft auf dem eigenen iPhone-17-Pro-Simulator „Werkstatt-Prototyp“ mit iOS 27 in Xcodes Device Hub. Am 15.10.2026 bestehen alle 48 XCTest-Kerntests und alle fünf UI-Tests. Der Mac-Bestand wurde über die normale Sicherungs-Wiederherstellung in den getrennten Prototyp übernommen und dort geprüft. Noch kein signierter oder auf einem echten iPhone geprüfter Release. Der genaue Prüfstand steht in `TEST_REPORT.md`.

## Enthalten

- Eigene lokale Fotokopien via Fotos-Auswahl oder Kamera; mehrere Stapel ohne 20-Artikel-Limit. Importfehler bleiben sichtbar, erfolgreiche Fotos werden behalten.
- Inbox, ausdrückliche Gruppierung pro Artikel, SHA256-Duplikaterkennung und automatische Ablage unter `bearbeitet/<Artikel-ID>/`. Originale bleiben byteidentisch; die Kamera liefert eine eigene JPEG-Aufnahme.
- Lokale Apple-Vision-Texterkennung für Beschriftungen. Klare Wörter liefern Modellhinweise; sie ist keine vollständige KI-Bildanalyse und recherchiert keine Preise. Fotos ohne Beschriftung können über den Chat analysiert werden.
- Geführte Auswahlkarten für Zustand, konkrete Mängel, Funktion, Akku, Ladekabel, Verpackung, Drehen/Höhenverstellung und Übergabe. Nach neuer Erfassung oder Analyseimport öffnet sich der Fragenablauf. Nur zur gewählten Artikelart passende Karten werden gestellt.
- „Nach meiner Einschätzung gut“ beim Akku ist gültig, ohne Prozentwerte zu erfinden. „Nicht gemessen“ bleibt ohne Akkubehauptung; „Noch prüfen“ bei Funktion verhindert die Freigabe. „Neu“ behauptet nicht automatisch „versiegelt“.
- Kompakte Angebotsansicht mit Vorschau und Bereit-Aktion oben. Beschreibung zunächst auf drei Zeilen; Fotos, Preisbegründung, Vergleiche, Analyse und Export lassen sich bei Bedarf öffnen. Bestätigte Antworten und manuelle Änderungen haben Vorrang vor Analysevorschlägen.
- Angebotsvorschau mit Fotos, Titel, Preis und Beschreibung sowie Umschaltung zwischen Vinted und Kleinanzeigen. Die Beispielansicht ändert die Zielplattform erst nach „Für … vorbereiten“; bei Verschenkangeboten ist nur Kleinanzeigen verfügbar.
- Veröffentlichungen getrennt vom nächsten Bearbeitungsstand speichern: Über das Symbol neben dem Status die bereits verwendeten Marktplätze bestätigen und optional öffentliche Links ergänzen. Die App veröffentlicht dadurch nichts.
- Chat-Austausch als ZIP mit ausgewählten, von EXIF/GPS bereinigten JPEGs und revisionsgebundener JSON-Anfrage. Keine API-Schlüssel, Cloud-KI, Anmeldung am Marktplatz oder automatische Veröffentlichung.
- Anzeigenpakete, lokale Metadatensicherungen und vollständige ZIP-Sicherung/Wiederherstellung. Wiederherstellung benötigt Bestätigung; der bisherige Bestand bleibt zusätzlich im App-Dokumentenordner erhalten.

## In Xcode starten

1. Xcode aus Apples App Store installieren, einmal öffnen und die iOS-Plattformunterstützung installieren.
2. `WerkstattApp.xcodeproj` öffnen. Scheme **Werkstatt** wählen.
3. Einen iPhone-Simulator auswählen und **Run** starten. Xcode 27 zeigt ihn in **Device Hub**. Der bereits angelegte Simulator heißt **Werkstatt-Prototyp**. Fotos-Auswahl ist geprüft; der Kameratest auf einem echten iPhone steht noch aus.
4. Für dein echtes iPhone unter **Signing & Capabilities** dein Team auswählen, das gekoppelte iPhone als Ziel wählen und Run starten. Apple-Account, Signierung und Developer Mode erfolgen über Xcode beziehungsweise dein Gerät.

Apple beschreibt den aktuellen Ablauf in [Running your app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices). Noch keine TestFlight- oder App-Store-Veröffentlichung eingerichtet.

Simulator-Build im Terminal, sobald Xcode verfügbar ist:

```sh
./ios/scripts/build.sh
```

Für die vorbereiteten UI-Tests einen verfügbaren iPhone-Simulator aus `xcrun simctl list devices available` wählen und dessen UUID übergeben:

```sh
./ios/scripts/test_simulator.sh <Simulator-UUID>
```

Die fünf bestandenen UI-Tests prüfen den Uhren-Fragenablauf mit qualitativem Akku, Originalverpackung und Neustart, neue Kopfhörer mit separat abgefragter Verpackung sowie Stuhlfragen ohne Akku, die kompakte Detailansicht mit eingeklapptem Preis und Plattformvorschau sowie den Veröffentlichungsstatus unabhängig von Pflichtantworten und über einen Neustart hinweg. Künstliche Testartikel werden ausschließlich in Debug-Simulator-Builds mit einer eigens gesetzten Test-ID erzeugt und liegen getrennt vom echten Bestand. Testergebnisse landen unter `ios/TestResults/` und bleiben außerhalb von Git.

Keine externen Paketabhängigkeiten; `WerkstattCore` ist ein lokales Swift-Package. Das Projekt lässt sich mit `python3 ios/scripts/generate_project.py` reproduzierbar erzeugen. Signierteam bleibt bewusst leer, damit kein Konto oder Zertifikat im Repository landet.

## Bestehenden Mac-Bestand übernehmen

Ein schreibgeschützter Export kopiert Originale, Vorschauen, Quellen und Artikel in das iOS-Sicherungsformat:

```sh
python3 ios/scripts/bridge.py export --output exports/ios/Bestand-fuer-iPhone.zip
```

Die ZIP anschließend in der App unter **Einstellungen → Sicherung wiederherstellen** auswählen. Der Mac-Bestand wird nicht verändert. Bestätigt veröffentlichte Artikel behalten die sichtbare Kennzeichnung **Eingestellt**. Fehlende strukturierte Antworten betreffen die Vorbereitung der nächsten Änderung und setzen eine bestehende Veröffentlichung nicht zurück. Alte Sicherungen mit dem eindeutigen Importvermerk `Mac-Fortschritt vor dem Umzug: published.` werden einmalig ergänzt; aus „Bereit“ oder einem Entwurfslink wird keine Veröffentlichung abgeleitet. Für weitere bereits öffentliche Anzeigen lässt sich die Bestätigung in der App nachtragen. Die neuen `publications`-Einträge sind abwärtskompatibel optional; `status` bleibt der lokale Arbeitsstand. Die Auswahl interner Belegfotos wird übernommen.

## Analyse über den Chat

1. In der App Fotos eines Artikels zuordnen, Beschriftungen auslesen und Auswahlfragen beantworten. Titelbild und Preis können noch offen bleiben.
2. **Für Chat exportieren** teilen. Die ZIP enthält `analysis-request.json`, `LIESMICH.txt` und `photos/<Foto-ID>.jpg`. Nicht ausgewählte Belegfotos, private Notizen und Seriennummer-Hinweise werden ausgelassen. Falls für die Modellprüfung ein Etikettfoto benötigt wird, wähle es ausdrücklich aus und prüfe private Angaben vor dem Teilen.
3. Im Chat alle ausgewählten Bilder prüfen und Marktpreise recherchieren lassen. Für den Import wird eine Datei `analysis-response.json` zurückgegeben, keine Änderung an der iPhone-Datenbank.
4. Datei im selben Artikel unter **Analyse & Details → Analyse importieren** öffnen. Artikel-ID und Revision müssen passen; zwischenzeitliche Änderungen werden nicht überschrieben. Aus der Analyse kommen weitere prüfbare Hinweise; bestätigte Verkäuferantworten bleiben erhalten. Danach öffnet sich der Fragenablauf.
5. Beschreibung prüfen, Titelbild auswählen, Preis festlegen und **Als bereit markieren**. Erst dann lässt sich das Anzeigenpaket teilen. Auf Vinted oder Kleinanzeigen selbst ausfüllen und veröffentlichen.

`Examples/analysis-response.example.json` zeigt das Format mit absichtlichen Platzhaltern. ID, Revision und ausgewählte Foto-IDs müssen aus der Anfrage übernommen werden. Der `photoOrder` enthält genau die ausgewählten Anfrage-Fotos; interne Fotos werden automatisch dahinter einsortiert. Ein Preisvorschlag braucht `sources` mit HTTPS-URL, Prüfdatum, Typ und eine Begründung in `pricingNote`. Keine Felder `condition`, `answers`, `description`, `status` oder `platform` importieren: diese bleiben unter Verkäuferkontrolle.

Zum sicheren Lesen eines iOS-Analysepakets auf dem Mac:

```sh
python3 ios/scripts/bridge.py inspect /absoluter/pfad/Analyse.zip
```

## Speicherung und Grenzen dieser Version

Der Bestand liegt im App-Dokumentenordner unter `Werkstatt/library.json`, Originale unter `inbox/` oder `bearbeitet/`, Vorschauen unter `previews/`. Metadaten werden atomar gespeichert; vor Änderungen bleiben bis zu 30 vorherige Versionen unter `backups/`. Diese Metadatensicherungen ersetzen keine vollständige Fotosicherung.

Die ZIP-Schnittstelle unterstützt unkomprimierte ZIP-Einträge, maximal 64 MB je Datei und 256 MB pro Paket. Größere Bestände lassen sich speichern, benötigen für vollständige Sicherungen aber künftig einen Export, der große Datenmengen direkt auf die Festplatte schreibt. Komprimierte, verschlüsselte oder unsichere ZIP-Dateien werden mit verständlichem Fehler abgewiesen. Die App hat keine Hintergrundsynchronisierung, keine selbstständige Marktpreisprüfung und keine automatische visuelle Zustandsbewertung.

Fotos verlassen die App nur über eine von dir gestartete Teilen-Aktion; Betriebssystem-Sicherungen und der von dir gewählte Zielanbieter haben ihre eigenen Einstellungen. JPEG-Anzeigenexporte werden neu geschrieben und enthalten keine übernommenen EXIF/GPS-Daten. Vorsichtig erkannte Seriennummer-Etiketten bleiben zunächst vom Export ausgeschlossen. Prüfe die Auswahl trotzdem selbst. Das Privacy-Manifest beschreibt Metadatenzugriffe im App-Ordner beziehungsweise auf ausdrücklich ausgewählte Dokumente anhand [Apples Gründe für Dateimetadatenzugriffe](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Prüfungen

Mit funktionierendem Xcode-Toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path ios/WerkstattCore --scratch-path /private/tmp/werkstatt-swift-xctest
./ios/scripts/build.sh
```

Xcode wird pro Befehl ausgewählt; die systemweite Toolchain-Einstellung bleibt unverändert. Der temporäre SwiftPM-Buildordner verhindert einen auf dem Desktop beobachteten Signierungsfehler durch Finder-Metadaten. Falls nur die zuvor installierten Command Line Tools zur Verfügung stehen, kompiliert diese Alternative den tatsächlichen Swift-Kern und führt die bestehenden Testkörper mit einem temporären Assertion-Harness aus:

```sh
python3 ios/scripts/check_core.py
python3 ios/scripts/check_native.py exports/ios/Bestand-fuer-iPhone-2026-10-15.zip
python3 -m unittest discover -s ios/tests -v
python3 -m unittest discover -s tests -v
node --check web/app.js
```

Der direkte Swift-Harness ist **kein XCTest-Lauf** und prüft weder SwiftUI-Typen noch iOS-SDK, Signierung oder UI-Verhalten. Tests verwenden temporäre Bestände. Der tatsächliche Mac→Swift-ZIP-Umzug mit vier Artikeln und neun Fotos sowie JPEG-Bereinigung und Bildausrichtung wurden zusätzlich direkt geprüft. Die vollständige Gerätetest-Liste steht in `DEVICE_CHECKLIST.md`.

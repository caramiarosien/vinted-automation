# Prüfstand am 15.10.2026

Der erste native Prototyp läuft in Xcodes Device Hub im eigenen iPhone-17-Pro-Simulator **Werkstatt-Prototyp**, iOS 27.0 (24A434). Eine Kopie des Mac-Bestands ist dort geladen. Noch kein signierter oder auf einem physischen iPhone geprüfter Release.

## Bestanden

- App und UI-Testziel mit Xcode 27.0 (27A266a), iOS-Simulator-SDK 27.0, Mindestziel iOS 17 gebaut.
- **48 echte XCTest-Kerntests, 0 Fehler** mit der vollständigen Xcode-Toolchain. Die zusätzliche Swift-Testing-Meldung mit 0 Tests bezeichnet einen separaten Runner.
- **Fünf UI-Tests, 0 Fehler** auf dem iPhone-Simulator: Uhr mit Zustand, Funktion, qualitativem Akku, Ladekabel, Verpackung und App-Neustart; neue Kopfhörer mit geöffneter Originalverpackung ohne erfundene Funktionsprüfung; Stuhl ohne Akku-Frage; kompakte Detailansicht mit Preis-Aufklappen und Plattformvorschau; bestätigte Veröffentlichung trotz offener Pflichtfragen mit Neustart. Letzter vollständiger Lauf: 16:14 Uhr, 183,84 Sekunden. Ergebnis: `ios/TestResults/Simulator-20261015-161142-44927.xcresult`.
- Sieben Python-Bridge-Tests und 14 Pipeline-Tests erneut bestanden; JavaScript-Syntaxprüfung bestanden.
- Private Mac-Sicherung über die tatsächliche iPhone-Dateiauswahl und den normalen Wiederherstellungsdialog eingelesen. **Vier Artikel, neun Originalfotos** erscheinen im Prototyp. Alle neun Originaldateien anschließend schreibgeschützt gegen ihre SHA256-IDs geprüft.
- Fotoauswahl über den System-PhotosPicker mit einer in die Simulator-Mediathek kopierten vorhandenen Kopfhöreraufnahme geprüft. Die Duplikaterkennung behielt den bestehenden Artikel; weiterhin vier Artikel und neun Fotos.
- Fragen an der echten Uhrenkopie sichtbar durchgespielt. Qualitative Akkuangabe und geöffnete Originalbox erscheinen in der neu erstellten Beschreibung; keine internen redaktionellen Notizen, normale Gebrauchsspuren nur einmal.
- Auch nach einem vollständigen Simulator-Neustart bleibt der Bestand erhalten. Der Prototyp ist abschließend in der Artikelübersicht geöffnet.
- JPEG-Bereinigung, Ausrichtung und Größenbegrenzung sowie Python→Swift-Sicherungsformat zusätzlich direkt geprüft.

Künstliche UI-Testartikel liegen in separaten Testordnern. In der Simulator-Kopie wurden die Fragen der Uhr und anschließend die Veröffentlichungszuordnungen von Uhr/Stuhl bearbeitet; der Mac-Katalog und seine Originalfotos wurden nicht geändert. Es wurde nichts auf einem Marktplatz veröffentlicht.

## Überarbeitung der Angebotsansicht

- Vorschau und Bereit-Aktion direkt unter dem Artikelkopf. Bei bereits öffentlichen Anzeigen betrifft „Änderung bereit“ die nächste Fassung; der sichtbare Status bleibt „Eingestellt“.
- Beschreibung zunächst auf drei Zeilen. Fotos, Preisbegründung/Vergleiche, Analyse und Export sind geschlossen und gezielt aufklappbar; Quellen haben eigene Detailbereiche.
- Vorschau mit tatsächlichen ausgewählten Fotos, Titel, Preis und Beschreibung. Umschaltung Vinted/Kleinanzeigen, bei Verschenken nur Kleinanzeigen. Ein Plattformwechsel in der Vorschau allein speichert keine Änderung.
- Veröffentlichungen je Marktplatz unabhängig vom Arbeitsstatus gespeichert, mit optionalen öffentlichen Links. Alte Importvermerke werden einmalig übernommen; keine Rückschlüsse aus „Bereit“ oder Entwurfslinks. Fehlende Pflichtantworten bleiben für eine neue Freigabe relevant.
- Der Veröffentlichungsablauf wurde nach der abschließenden Speicherknopf-Anpassung nochmals gezielt geprüft: 1 UI-Test, 0 Fehler um 16:20 Uhr, Ergebnis `ios/TestResults/Publication-Form-20261015-1622.xcresult`.
- 48 XCTest-Kerntests und der direkte 48-Fälle-Swift-Harness bestanden. Neue Tests prüfen Sicherungskompatibilität, Migration, Neustart, öffentliche Links und die weiterhin wirksame Freigabevalidierung.
- Beim ersten UI-Lauf fielen ein unzuverlässig betätigter Formularschalter, ein kollabierter Bereich im Accessibility-Baum und das Wegwischen des Fragenblatts durch eine Testgeste auf. Marktplatzbestätigung erfolgt nun über explizite Auswahlzeilen, Preisdetails existieren nur geöffnet, Testgesten zielen auf die Scrollansicht. Der Fragenabschluss steht oben und jede neue Frage startet am Anfang.

## Behobene Befunde

- Konkrete Simulator-Tests mischten zuvor den arm64-Paketbuild mit einem x86_64-App-Build. Debug-Ziele verwenden jetzt konsistent die aktive Architektur; der erneute Testlauf besteht.
- Eine migrierte Formulierungsnotiz konnte als sichtbarer Zustandshinweis in die Beschreibung geraten. Redaktionelle Begriffe werden ausgeschlossen, allgemeine Gebrauchsspuren nicht doppelt übernommen. Regressionstest ergänzt; konkrete Macken bleiben erhalten.
- Uhren fragen die Verpackung jetzt ausdrücklich ab, damit die Originalbox beim Erstellen der Beschreibung erhalten bleibt.
- SwiftPM-Builds im Desktop-Ordner scheiterten an Finder-Metadaten beim lokalen Signieren. Erfolgreiche XCTest-Builds nutzen einen temporären Scratch-Ordner. Xcode-System-Caches benötigen regulären Zugriff außerhalb der Dateisandbox.

Die bestehende Kleinanzeigen-Sitzung wurde ausschließlich lesend abgeglichen: Uhr und Stuhl sind online. Die öffentliche Vinted-Uhr wurde ebenfalls aufgerufen und ist verfügbar. In der App sind deshalb zwei veröffentlichte Artikel mit insgesamt drei Plattformzuordnungen gespeichert: Uhr auf Vinted/Kleinanzeigen, Stuhl auf Kleinanzeigen. Die Links wurden über das normale Veröffentlichungsformular eingetragen. Anschließend schreibgeschützt geprüft: vier Artikel, neun Originalfotos mit passenden SHA256-IDs und genau drei Veröffentlichungszuordnungen auf zwei Artikeln. Preise und Beschreibung der gespeicherten Entwürfe bleiben eigenständig; dies ist kein laufender Marktplatzabgleich.

Sichtbar auf echten Beispieldaten geprüft: kompakte Uhrenansicht, Öffnen und erneutes Schließen der Preisrecherche, Original-Titelbild zuerst, vier ausgewählte Vorschaufotos statt des internen fünften Belegfotos, Wechsel Vinted/Kleinanzeigen ohne Speichern einer neuen Zielplattform und korrigierte Statusübersicht.

## Noch offen vor einem Release

- Physisches iPhone: Team/Signierung, Installation, Kamera erlauben/ablehnen, echte HEIC-/iCloud-Fotos, Hardware-/Akkubetrieb.
- Weitere manuelle UI-Prüfungen für Share Sheet/Export, Sicherungsabbruch, Analyse-JSON-Dateiauswahl und Fehlerdialoge. Deren Kernlogik ist automatisiert geprüft; nicht alle Betriebssystem-Dialogvarianten wurden manuell durchgespielt.
- VoiceOver, sehr große Schrift, Querformat, kleine Displays, wenig Speicher und längere Import-/Export-Stapel auf dem Gerät.
- Kein TestFlight- oder App-Store-Release. Analyse und Preisrecherche bleiben beim gewählten Chat-Austausch; die App veröffentlicht keine Anzeigen automatisch.

## Nachweise

Private Screenshots liegen außerhalb von Git in `exports/ios/prototyp/`: `01-werkstatt.png`, `02-akku-fragen.png`, `03-werkstatt-final.png`, `04-status-korrigiert.png`, `05-angebot-kompakt.png`, `06-vorschau-vinted.png` und `07-vorschau-kleinanzeigen.png`. Die vollständigen XCTest-Ergebnisdateien und Build-Artefakte bleiben ebenfalls außerhalb von Git.

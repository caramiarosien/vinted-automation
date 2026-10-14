# Vinted Werkstatt

Lokale Anzeigenvorbereitung für wiederkehrende Fotostapel. Der Bestand hat kein 20-Artikel-Limit. SQLite speichert Artikel, Zuordnungen und Fortschritt über Neustarts hinweg. Die Bildanalyse erfolgt über den Chat; diese Anwendung macht keine KI-API-Aufrufe und greift nicht auf dein Vinted-Konto zu.

## Start

Für eine neue Installation das Repository klonen, in den Projektordner wechseln und die Umgebung vorbereiten:

```sh
git clone https://github.com/caramiarosien/vinted-werkstatt.git
cd vinted-werkstatt
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python pipeline.py serve
```

`Start.command` doppelklicken oder im Projektordner `python3 pipeline.py serve` starten. Die Oberfläche läuft unter http://127.0.0.1:8765. Das Terminal geöffnet lassen. Zum Beenden Ctrl+C drücken.

Benötigt Python 3.11+ und Pillow. Falls Pillow fehlt: `python3 -m venv .venv` und `.venv/bin/pip install -r requirements.txt` ausführen. Mit `.venv/bin/python pipeline.py serve` starten.

## Dein Ablauf

1. Neue Bilder in `inbox/` legen. Unterordner sind möglich. Bestehende Bilder im Projektordner werden ebenfalls eingelesen. Die Originale bleiben erhalten.
2. „Neue Fotos einlesen“ klicken. Identische Dateien werden anhand ihres Inhalts erkannt. Fotos mit gleichem Dateinamen und unterschiedlichem Inhalt bleiben getrennt. Ein Importfehler blockiert die anderen Fotos nicht und wird bei einem erneuten Import erneut versucht.
3. Im Chat schreiben: „Bereite die neuen Vinted-Fotos vor.“ Die Analyse verwendet das aktuelle Manifest, betrachtet die Vorschaubilder, recherchiert Modell/Preis und importiert die Ergebnisse. Neue Fotos können auch einem bestehenden Entwurf zugeordnet werden; bei ähnlich aussehenden Gegenständen die Zuordnung prüfen.
4. Entwurf prüfen. Offene Fragen beantworten, die Beschreibung ergänzen, Zustand und Preis eintragen. Rückfragen erst nach Klärung abhaken. Die Kategorie ist ein Vorschlag, den du in Vinted mit den dort verfügbaren Kategorien abgleichst.
5. „Prüfung abschließen“ klicken und das Anzeigenpaket herunterladen. Es enthält ausgewählte Fotos als JPEG ohne EXIF-Daten, Titel, Beschreibung und Artikeldaten. Bei echten HEIC-Dateien, die nur per macOS-Konvertierung lesbar sind, verwendet der Export die 1600px-Vorschau.
6. Selbst in Vinted eingeben und veröffentlichen. Danach Fortschritt auf „Eingestellt“ ändern und optional den Anzeigenlink eintragen.

„Ausgewählte Fotos verschieben“ unter einem Entwurf verschiebt die angehakten Anzeigenfotos zum gewählten Ziel oder zurück in die Warteschlange. Die internen Belegfotos sind zunächst nicht angehakt. Änderungen der Fotozuordnung sind nur bei Entwürfen möglich. Ein leer gewordener Entwurf kann auf „Archiv“ gesetzt werden.

## Titelbild und Preis

Bei der Analyse werden sämtliche Bilder pro Artikel verglichen. Das gespeicherte Titelbild steht in der Kartenansicht und im Export zuerst. Die Radioauswahl „Als Titelbild“ erlaubt eine manuelle Änderung; sie wählt das Foto auch für den Export aus. Ein Titelbild muss zum Artikel gehören und als Anzeigenfoto ausgewählt sein. `photo_order` legt die Reihenfolge weiterer Fotos fest. Deine ausdrückliche Auswahl hat Vorrang vor späteren Analysevorschlägen. Die Begründung steht unter den Fotos; sie ist eine Einschätzung der Präsentation, keine gemessene Klickprognose.

`pricing_note` speichert die Preisempfehlung und ihre Herleitung. Die darunter verlinkten Quellen enthalten Vergleichspreise, Datum und Unterschiede. Diese privaten Recherchehinweise werden nicht in die öffentliche Beschreibung übernommen. Der Endpreis ist jederzeit editierbar.

Die Recherche im Chat prüft Kleinanzeigen, eBay und Vinted sowie passende weitere Gebraucht-, Händler- und Ankaufplattformen. Wenn verfügbar, werden etwa 8–12 unabhängige private Angebote derselben Modellvariante betrachtet. Unterschiede bei Zustand, Zubehör, Farbe und Land werden festgehalten. Dubletten desselben Artikels auf mehreren Plattformen zählen einmal; falsche Größen/Funkvarianten, defekte Geräte und laufende Auktionsgebote zählen nicht zur Kernstichprobe. Die Recherche dokumentiert auch Plattformen ohne verwendbaren Preis.

Die Preisempfehlung trennt einen Startpreis mit Verhandlungsspielraum von einer optionalen Strategie für einen schnelleren Verkauf. Angebotspreise, tatsächlich belegte Verkaufspreise, Händlerverkauf und Händlerankauf werden getrennt bewertet. Ein als verkauft markiertes Angebot beweist bei möglichem Preisvorschlag nicht den endgültig gezahlten Betrag. Die Bereiche sind Schätzungen und keine Zusage für Erlös oder Verkaufsdauer. Vergleichspreise müssen vor einem späteren Einstellen erneut geprüft werden.

## Für die Analyse im Chat

`python3 pipeline.py manifest` liefert neue Fotos mit absolutem Vorschaubildpfad und den bisherigen Bestand. Nur Fotos ohne Importfehler analysieren. Immer Bildinhalte prüfen, nicht nach Dateinamen oder Aufnahmezeiten gruppieren. Pro Artikel Bildbelege und Unsicherheiten festhalten. Funktion, Material, Lieferumfang, Zustand und Preise nicht erfinden. Nummern auf Etiketten nicht in die öffentliche Beschreibung übernehmen. Preisquellen mit Datum und Hinweis auf Angebots- oder Verkaufspreis speichern.

Neue Artikel werden mit `python3 pipeline.py apply datei.json` importiert:

Im `item`-Objekt zusätzlich `cover_photo_id` auf ein ausgewähltes Bild aus `photo_ids` setzen, eine kurze `cover_reason` angeben und optional `photo_order` mit der Reihenfolge aller Artikelbilder ergänzen. Für eine ausdrückliche Benutzerwahl gilt `cover_origin: "manual"`, sonst `"analysis"`. Ohne Titelbild bleibt der Entwurf in Prüfung. Die optionale `pricing_note` enthält die begründete Preisempfehlung.

```json
{"groups":[{"photo_ids":["sha256-aus-manifest"],"exclude_photo_ids":[],"item":{"title":"Titel","description":"Nur belegte Angaben","brand":"Marke","category":"Kategorie-Vorschlag","size":"","color":"","condition":"","price":null,"facts":["Beobachtung und Bildbeleg"],"questions":["Offene Frage"],"sources":[],"notes":""}}]}
```

Quellenformat: `{"title":"Quelle","url":"https://…","checked":"YYYY-MM-DD","note":"Einordnung","price":123}`. Preis ist optional. Alle Imports bleiben zunächst Entwürfe. Bereits zugeordnete Fotos werden beim Import abgewiesen, damit wiederholte Analyseimporte keine doppelten Artikel erzeugen. Das Dokument wird vollständig geprüft und atomar übernommen.

Bestehende Entwürfe: `Store().update(item_id, changes, revision)` verwenden; die aktuelle `revision` steht im Manifest. Ein Revisionskonflikt verhindert das Überschreiben neuerer Änderungen. Die Fotozuordnung kann mit `Store().regroup(photo_ids, item_id)` korrigiert werden. Bestehende Artikel werden nicht allein aufgrund ähnlicher Optik automatisch zusammengeführt.

## Speicherung und Wiederherstellung

`data/catalog.sqlite3` ist die dauerhafte Datenbank. `data/images/` enthält Vorschaubilder; `data/backups/` Datenbanksicherungen vor Analyseimporten und beim Start. Die Tabelle `events` hält Artikelversionen vor und nach Änderungen fest. Für eine vollständige Sicherung den gesamten Projektordner kopieren, einschließlich Originalfotos und `inbox/`. Für eine Wiederherstellung zuerst den Server stoppen; Datenbanken nie bei laufendem Server ersetzen.

Das GitHub-Repository enthält den Programmcode, die Anleitung und die Tests. `.gitignore` schließt Fotos, `inbox/`, `data/`, `exports/`, lokale Zugangsdaten und Python-Umgebungen aus. Ein Git-Push sichert deshalb nicht deinen Artikelbestand. Beim Start einer frischen Installation werden die lokalen Datenordner automatisch angelegt.

## Prüfungen

`python3 -m unittest discover -s tests -v`

`node --check web/app.js`

Die Oberfläche bindet ausschließlich an 127.0.0.1, stellt nur bekannte Vorschaubilder bereit und schützt Schreibaktionen mit einem Sitzungstoken. Passwörter oder Vinted-Sitzungen werden nicht benötigt. Das automatische Ausfüllen oder Veröffentlichen bei Vinted ist nicht implementiert.

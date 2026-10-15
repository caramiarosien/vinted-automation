# Geräte- und Release-Prüfung

Aktueller Prüfstand: `TEST_REPORT.md`. App-Build, 48 XCTest-Kerntests und fünf UI-Tests bestehen. Der Prototyp läuft mit einer Kopie des Bestands im iPhone-Simulator. Die verbleibenden Geräte- und Dialogprüfungen sind vor einem Release noch offen.

Xcode 27 und iOS 27 sind eingerichtet. Device Hub zeigt den eigenen Simulator „Werkstatt-Prototyp“. Sichtbar geprüft sind Sicherungs-Wiederherstellung, Fotoauswahl/Duplikaterkennung sowie der Uhren-Fragen- und Beschreibungsablauf. Der Bestand blieb auch nach Simulator-Neustart erhalten. Die kompakte Angebotsansicht, das Preis-Aufklappen und beide Plattformvorschauen sind mit echten Beispieldaten sichtbar geprüft. Die Uhr ist auf Vinted und Kleinanzeigen, der Stuhl auf Kleinanzeigen als veröffentlicht zugeordnet; öffentliche Anzeigen wurden dafür ausschließlich lesend abgeglichen.

- [x] Simulator-Build und UI-Test-Build: Scheme Werkstatt, generisches iOS-Simulatorziel, keine Signierung erforderlich, keine Compilerfehler.
- [x] Frischer Start mit leerer Inbox, System-Fotoauswahl und Duplikaterkennung. Kamera und sämtliche Abbruchvarianten bleiben Teil der Geräteprüfung.
- Echtes iPhone: Team/Signierung, Kamera erlauben/ablehnen, Foto auswählen, HEIC mit gedrehter Orientierung, Aufnahme speichern, App beenden und erneut öffnen.
- Stapel: mehr als 20 Artikel über mehrere Importe; Dubletten, beschädigte Datei und erfolgreicher Restimport, dynamische Schriftgröße, VoiceOver, schmaler Bildschirm und Querformat.
- [x] Smartwatch: Zustand/Funktion/qualitativer Akku/Ladekabel/Verpackung und Neustart im UI-Test; qualitative Akkuangaben ohne erfundene Messwerte. Nicht gemessener Akku und ungeprüfte Funktion zusätzlich im Kern geprüft.
- [x] Kopfhörer neu: Verpackung separat, kein unbestätigtes „versiegelt“ oder „funktioniert“ im UI-Test. Funktionsfrage für gebrauchte Kopfhörer im Kern geprüft.
- [x] Stuhl: Drehfunktion/Höhe mit „funktioniert“ im UI-Test; konkrete Macke bleibt im Kern erhalten. Weitere Problem-/Nicht-vorhanden-Kombinationen manuell auf dem Gerät prüfen.
- Kategorienwechsel: alte artikelspezifische Antworten werden neu abgefragt, globaler Zustand bleibt erhalten.
- Analyse-JSON: richtige ID/Revision erfolgreich, falsche/revidierte Antwort abgewiesen, nur ausgewählte Fotos neu geordnet, manuelle Titelbildwahl/Verkäufertext bleiben erhalten, nächste Fragen öffnen sich.
- Belegfoto mit Seriennummer: lokale Erkennung, vom Export ausgeschlossen, bewusste Auswahl möglich. Analyseexport enthält keine privaten Notizen.
- Preise: Verkauf positiv, Verschenken nur Kleinanzeigen/0, nicht gemessene Verkaufserlöse werden nicht behauptet. Manuell gesetzter Preis bleibt erhalten.
- [x] Freigabe: draft→ready, published und sold ohne geklärte Pflichtfragen verhindern; Titel/Preis/Fotoauswahl prüfen. Bestätigte externe Veröffentlichungen werden separat gespeichert, ohne Antworten zu erfinden.
- [x] Kompakte Detailansicht: Vorschau/Bereit oben, Preisdetails öffnen/schließen und Vinted/Kleinanzeigen-Vorschau im UI-Test; Veröffentlichung über Neustart erhalten.
- Export: Share Sheet, Titel/Beschreibung kopieren, JPEGs ohne EXIF/GPS, Titelbild zuerst. Keine automatische Veröffentlichung.
- Sicherung: App-erzeugte ZIP wiederherstellen, Mac-Umzug öffnen, beschädigte/zu große/komprimierte/unsichere ZIP ablehnen und vorhandenen Bestand behalten.
- Wiederherstellung abbrechen; bestätigte Wiederherstellung mit bisherigen Daten im separat erhaltenen Ordner überprüfen.
- Betrieb bei wenig Speicher, langsamen Fotos aus iCloud, mehrfachen Share-Aktionen und Unterbrechung während Import prüfen.

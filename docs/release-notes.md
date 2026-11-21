## Polux 1.0.21

Polaroid-Inspirations-Widget für macOS (ab macOS 13, Apple Silicon und Intel).

**Neu in 1.0.21**
- Jeder Knopf im Polaroid gibt eine sichtbare Rückmeldung direkt im Foto:
  - **Herz:** großes rotes Herz ploppt im Bild auf („Like entfernt“ beim Zurücknehmen).
  - **Ordner:** „Zu „Sammlung“ hinzugefügt“.
  - **Zauberstab:** „Mehr davon: …“ bzw. „beendet“.
  - **Link:** „Quelle im Browser geöffnet“.
  - **Pause/Play:** großes Pause-/Play-Symbol mit „Pausiert“ / „Läuft wieder“.
  - **Vor/Zurück:** Pfeil im Bild, bei neuer Suche „Nächstes Foto wird gesucht …“.

**Neu in 1.0.20**
- „Passt nicht“ (Daumen runter) zeigt sofort eine Rückmeldung: Das Foto wird abgedunkelt mit „Passt nicht – suche Ersatz …“, bis das neue Foto da ist.
- Läuft gerade schon eine Suche, geht der Klick nicht mehr verloren.
- Das Herz bezieht sich immer auf das angezeigte Foto (vorher konnte es nach „Passt nicht“ den Zustand des vorherigen Fotos zeigen).
- Alle Knöpfe im Polaroid geben beim Klicken eine kurze sichtbare Rückmeldung.

**Neu in 1.0.19**
- Der Verbindungsstatus der Bildquellen bleibt nach einem Neustart erhalten („Verbunden“ statt „Bereit“).
- Kurz nach dem Start prüft Polux alle eingerichteten Quellen automatisch im Hintergrund.
- Beim Darüberfahren über den Status steht, wann zuletzt geprüft wurde.

**Neu in 1.0.18**
- DeviantArt-Anmeldung robuster: drei von DeviantArt unterstützte Anmeldearten werden nacheinander versucht; eingefügte Werte werden bereinigt (Leerzeichen, Zeilenumbrüche, Beschriftungen wie „client_id:“).
- Klare Fehlermeldung mit der Begründung von DeviantArt – und Unterscheidung, ob die Anmeldung oder erst der Bildabruf abgelehnt wurde.

**Neu in 1.0.17**
- **Filterprotokoll** (Sammlung → Reiter „Protokoll“): gefundene, passende, geprüfte und gezeigte Fotos, die häufigsten Gründe fürs Aussortieren, die letzten Suchen je Quelle und konkrete Tipps.
- **Klarere Meldung**, wenn keine passenden Fotos gefunden werden (z. B. „Keine Treffer zu den Schlagwörtern – mehr Schlagwörter?“).
- **Datensicherung** (Allgemein → Speicher): Sammlungen, Lieblingsfotos und Notizen als ZIP exportieren und wiederherstellen; optional wöchentlich automatisch in iCloud Drive (die letzten 4 bleiben erhalten).
- **Automatische Tests** prüfen bei jedem Update die Bildregeln, Pinterest-Adressen und Versionsnummern.
- Aufgeräumt: nicht mehr genutzte Reste früherer Versionen entfernt.

**Neu in 1.0.16**
- **Zielgenauere Vorschläge:**
  - Keine zufälligen „Ausreißer“-Fotos mehr (bisher wurde etwa jedes achte Foto absichtlich zufällig gewählt).
  - Schlagwörter strenger: allgemeine Wörter („dark“, „art“, „photo“ …) zählen nur halb – mindestens ein prägendes Wort des Schlagworts muss passen. Fotos ohne Beschreibung werden nicht mehr ungeprüft gezeigt.
  - Die Bilderkennung prüft das Schlagwort zusätzlich am Bild.
  - Plakate, Screenshots, Memes und Bilder mit viel Text sowie extreme Panorama-/Streifenformate werden aussortiert; Mindestgröße 480 px.
- **Neuer Knopf „Passt nicht“ (Daumen runter)** im Polaroid: Polux merkt sich den Stil als unerwünscht und zeigt sofort das nächste Foto.
- Die Beschriftung im Polaroid zeigt jetzt, **zu welchem Schlagwort** das Foto gefunden wurde.

**Neu in 1.0.15**
- Pinterest zuverlässiger: bis zu drei Versuche mit kurzer Pause, wenn Pinterest eine Anfrage abweist; gefundene Boards zu Pins werden gemerkt; ist Pinterest kurz nicht erreichbar, nutzt Polux die zuletzt geladenen Bilder (bis 48 Stunden) weiter.

**Neu in 1.0.14**
- Pinterest: Ist statt eines Boards ein **einzelner Pin** eingetragen (z. B. ein geteilter pin.it-Link), ermittelt Polux automatisch das Board, auf dem der Pin gespeichert ist, und nutzt dessen Feed.
- Klarere Anleitung, wie man in App und Browser den Board-Link kopiert.

**Neu in 1.0.13**
- **Schlagwörter haben Vorrang:** Gesucht wird nur noch nach den eigenen Schlagwörtern (keine automatisch angehängten Begriffe mehr). Treffer müssen zum Schlagwort passen – unscharf: Wortstamm, Plural und kleine Tippfehler zählen mit (bei „editorial gothic“ genügt eines der Wörter). Passende Bilder werden zuerst gezeigt.
- **Ausschlusswörter** greifen als ganze Wörter („man“ schließt nicht mehr „woman“ aus), erkennen Varianten und prüfen auch die Bilderkennung.
- **Pinterest:** Länder-Adressen (pinterest.de), Kurzlinks (pin.it), Profile und Board-Abschnitte werden automatisch in die richtige Feed-Adresse umgewandelt; Abruf wie ein Browser; verständliche Fehlermeldungen.
- **Boards eintragen** geht jetzt direkt im Pinterest-Fenster je Sammlung. Wird Pinterest in einer Sammlung eingeschaltet, rückt das Eingabefeld nach oben und leuchtet kurz auf.

**Neu in 1.0.12**
- Filter an Dark-Fine-Art-, Akt-, Hochzeits- und Paarfotografie angepasst – weniger Fehlausschlüsse:
  - Hochzeits-/Paarfotos vor Kirche, Burg, Torbogen oder im Wald bleiben erlaubt („wedding“, „groom“, „Hochzeit“ … zählen als Personenhinweis).
  - Detailaufnahmen (Hände mit Ringen, Anstecker) zählen über die Bilderkennung als Bilder mit Personen.
  - „altar“, „medieval“, „century“ und „fantasy“ sperren nicht mehr (Trauung, Kostüm- und Dark-Fantasy-Shootings).
  - Dunkle, entsättigte Bodypaint-Akte werden nicht mehr fälschlich als Malerei erkannt.
  - „digital art“ & Co. sind erlaubt, wenn Titel/Tags Fotorealismus betonen.

**Neu in 1.0.11**
- Nur noch Fotos und **fotorealistische** KI-Bilder: gemalte/gezeichnete Digitalkunst und Illustrationen werden aussortiert – über Titel/Tags (z. B. „digital art“, „art nouveau“, „fantasy art“), per Bilderkennung bei allen Quellen und über extrem gesättigte Farben.
- ArtStation ist für neue Sammlungen wieder standardmäßig aus (liefert überwiegend gemalte Kunst).

**Neu in 1.0.10**
- „Nur Bilder mit Personen“ deutlich strenger: Es zählen nur gut sichtbare Personen (keine Statuen oder Passanten in der Ferne); Bilder, die sich nicht prüfen lassen, werden aussortiert.
- Architektur, Landschaft und Stadtansichten ohne Menschen werden auch über Titel/Tags erkannt.
- Suchanfragen ohne Personenbezug werden automatisch um „portrait“ ergänzt.

**Neu in 1.0.9**
- Keine abfotografierten Gemälde mehr: Openverse liefert nur noch aus echten Fotoquellen (Flickr, StockSnap, WordPress-Fotos) statt aus Museums-/Wikimedia-Archiven.
- Zusätzliche Erkennung von Alten Meistern, Altarbildern und Museumsbeständen über Titel/Tags und per Bilderkennung (außer bei Digitalkunst von ArtStation).

**Neu in 1.0.8**
- Feinere Bildregeln: Fotos sowie **Digitalkunst und KI-Bilder mit Personen** sind erlaubt. Aussortiert werden klassische Gemälde und Zeichnungen, **Anime/Comic**, **Stillleben** und **Abstraktes**.
- Neue Option je Sammlung: **„Nur Bilder mit Personen“** (Standard: an) – geprüft per Bilderkennung.
- ArtStation ist für neue Sammlungen wieder aktiv.

**Neu in 1.0.7**
- **Updates installieren sich automatisch:** Polux prüft beim Start und alle 6 Stunden und installiert neue Versionen ohne Rückfrage (abschaltbar unter Einstellungen → Updates).
- Gemälde werden über Titel/Tags und per Bilderkennung aussortiert.

**Neu in 1.0.6**
- **Moodboard-Export:** In der Galerie Fotos auswählen und als Bild (JPEG) exportieren – Mosaik mit „polux“-Schriftzug, ganz unten eine kleine Fußnote mit Urheber und Lizenz.
- **Notizen & Look:** In der Großansicht der Galerie eigene Notizen hinterlegen (kleiner Post-it am Foto) sowie Farbpalette und Licht-Einschätzung (Low-/High-Key, Kontrast, Farbtemperatur).
- **Personen-Prüfung am Bild:** Bei „Frau/Mann/Paar“ werden Fotos ohne erkannte Person aussortiert; passende Personenzahl wird bevorzugt.
- **Mehr davon:** Zauberstab im Polaroid (oder in der Galerie) sucht gezielt ähnliche Fotos.
- **Doppelte Bilder** werden erkannt und übersprungen – auch über verschiedene Quellen hinweg.

**Neu in 1.0.5**
- Neue Einstellung je Sammlung: **Person im Bild – Beliebig · Frau · Mann · Paar**. Polux ergänzt die Suche passend und sortiert Fotos aus, die laut Titel/Tags eindeutig nicht passen. Auch beim Anlegen einer neuen Sammlung wählbar.

**Neu in 1.0.4**
- Einstellungen neu gegliedert: Seitenleiste mit *Sammlungen*, *Bildquellen* und *Allgemein*.
- „Zugänge & Quellen“ als Kachel-Übersicht mit Status; „Einrichten …“ öffnet ein Fenster mit Schlüssel, Verbindungstest und Anleitung.
- Jede Sammlung mit Reitern *Suche*, *Quellen* und *Stil & Fotos* – inklusive Pinterest-Boards und Schnell-Einrichtung fehlender Schlüssel.
- „Neue Sammlung …“ fragt gleich Name, Schlagwörter und Bildsprache ab.

**Neu in 1.0.3**
- Doppelklick auf das Foto öffnet zuverlässig die Galerie.

**Neu in 1.0.2**
- **Updates mit einem Klick:** „Jetzt aktualisieren“ lädt die neue Version, ersetzt Polux und startet automatisch neu. Sammlungen, Likes und Einstellungen bleiben erhalten. Findet die tägliche Prüfung eine neue Version, fragt Polux einmal nach.
- Update-Prüfung fragt immer frisch bei GitHub nach.

**Neu in 1.0.1**
- Das Polaroid lässt sich an jeder Stelle verschieben – Rahmen, Ecken, Foto und Beschriftung.

**Hinweis:** Wer noch 1.0.0 oder 1.0.1 nutzt, installiert einmal von Hand (alte App ersetzen). Ab 1.0.2 geht jedes Update automatisch über „Jetzt aktualisieren“.

**Installation**
1. `Polux-1.0.21.zip` herunterladen und entpacken.
2. `Polux.app` in den Ordner **Programme** ziehen.
3. Beim ersten Start **Rechtsklick → Öffnen** (die App ist nicht von Apple notarisiert).
   Meldet macOS „beschädigt“: im Terminal `xattr -dr com.apple.quarantine /Applications/Polux.app` ausführen.

**Funktionen**
- Polaroid-Widget mit Fotowechsel (Standard: alle 5 Minuten), Pause, Vor/Zurück, Beenden über das x
- Sammlungen mit Schlagwörtern, Ausschlusswörtern, Akt-Option und Regler „Düstere Inszenierung“
- Likes mit Stil-Lernen direkt auf dem Mac (Vision), platzsparende HEIC-Speicherung
- Mosaik-Galerie per Doppelklick, Entfernen mit Neuberechnung des Stils
- Quellen: Openverse, ArtStation, Pinterest-Boards (RSS), Unsplash, Flickr, Pexels, DeviantArt – mit Verbindungstest
- Autostart, gemerkte Position, Update-Prüfung

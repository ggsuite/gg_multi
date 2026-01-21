# Kidney Handbuch

Praktische Kurzbeschreibung für den täglichen Einsatz von Kidney in Dart- und Flutter-Projekten.

Kidney unterstützt dich dabei, Multi Repo Projekte mit vielen Git Repositories konsistent zu verwalten. Kidney unterstützt derzeit nur Dart / Flutter.

---

## 1. Überblick und Installation

### 1.1 Was ist Kidney

Kidney ist ein Kommandozeilenwerkzeug für Multi Repo Projekte. Es hilft dir dabei

- alle Repositories eines Projekts zentral zu verwalten,
- pro Ticket eigene Arbeitskopien dieser Repositories anzulegen und
- Abhängigkeiten zwischen Repositories konsistent zu halten.

### 1.2 Voraussetzungen

Bevor du Kidney installierst, benötigst du

- Git
- Dart SDK (damit der Befehl `dart` verfügbar ist)
- optional Visual Studio Code inklusive `code` Kommando in deinem `PATH`

### 1.3 Installation

1. Repository klonen

   ```bash
   git clone https://github.com/ggsuite/kidney_core.git
   cd kidney_core
   ```

2. Installation ausführen

   - unter Linux und macOS

     ```bash
     ./install
     ```

   - unter Windows (PowerShell oder Eingabeaufforderung)

     ```bat
     install.bat
     ```

3. Installation prüfen

   ```bash
   kidney_core -h
   ```

Wenn die Hilfe angezeigt wird, ist Kidney einsatzbereit. Alle Beispiele in diesem Handbuch nutzen das Kommando `kidney_core`.

---

## 2. Arbeitsordner für Kidney anlegen

Für jedes Multi Repo Projekt solltest du einen eigenen, leeren Projektordner anlegen. In diesem Ordner verwaltet Kidney alle Repositories und Tickets.

Beispiel:

```bash
mkdir mein_projekt
cd mein_projekt
```

Alle folgenden Befehle in diesem Handbuch werden von diesem Projektordner oder dessen Unterordnern aus ausgeführt.

---

## 3. Workspace initialisieren mit `kidney_core init`

Im frisch angelegten, leeren Projektordner initialisierst du den Kidney Workspace:

```bash
kidney_core init
```

Was passiert dabei?

- Kidney prüft, ob der Ordner leer ist und nicht bereits innerhalb eines anderen Kidney Workspaces liegt.
- Es wird ein Unterordner `.master` angelegt. Dieser stellt den Master Workspace dar und enthält später die zentralen Klone deiner Repositories.

Ab jetzt erkennt Kidney deinen Workspace automatisch, wenn du Befehle irgendwo innerhalb dieses Projektordners ausführst.

---

## 4. Repositories zum Master Workspace hinzufügen

### 4.1 `kidney_core add <group_url>`

Mit `kidney_core add` fügst du Repositories in den Master Workspace unter `.master` hinzu.

Ein typischer erster Schritt ist das Hinzufügen aller Repositories einer Organisation oder Gruppe.

Beispiele für `group_url`:

- GitHub Organisation
  - `https://github.com/meine-org`
- Azure DevOps Organisation und Projekt
  - `https://dev.azure.com/meine-org/mein-projekt`
  - oder die entsprechende SSH Form `git@ssh.dev.azure.com:v3/meine-org/mein-projekt/mein-repo`

Ausführung im Projektordner:

```bash
kidney_core add https://github.com/meine-org
```

Was passiert?

- Kidney erkennt, dass es sich um eine Organisations- oder Projektadresse handelt.
- Alle Repositories dieser Gruppe werden in `.master` geklont.

### 4.2 Einzelne Repositories hinzufügen

Du kannst auch einzelne Repositories in `.master` hinzufügen:

- vollständige Git URL (https oder ssh), zum Beispiel
  - `kidney_core add https://github.com/meine-org/app_core.git`
- Kurzform `benutzername/repo`
  - `kidney_core add meine-org/app_core`
- nur der Reponame
  - `kidney_core add app_core`
  - in diesem Fall nutzt Kidney Konventionen (zum Beispiel `https://github.com/app_core/app_core.git`) und versucht zusätzlich bekannte Organisationen aus deinem Workspace.

### 4.3 Verhalten bei bereits vorhandenen Repositories

Wenn ein Repository im Master Workspace bereits existiert und nicht leer ist, wird es standardmäßig nicht überschrieben. Kidney protokolliert dann nur, dass das Repository schon vorhanden ist.

Mit der Option `--force` kannst du das Repository im Master Workspace trotzdem neu klonen:

```bash
kidney_core add --force https://github.com/meine-org/app_core.git
```

Nutze `--force` nur, wenn du sicher bist, dass du den bestehenden Klon ersetzen möchtest.

---

## 5. Ordnerstruktur verstehen (`.master` und `tickets`)

Nach `kidney_core init` und den ersten `add` Befehlen sieht eine typische Struktur so aus:

```text
mein_projekt/
  .master/
    app_core/
    ui_core/
    shared_widgets/
  tickets/
    (noch leer)
```

- `.master` enthält die zentralen Repositories deines Projekts.
- `tickets` ist der Bereich für deine Ticket Workspaces. Für jedes Ticket wird hier ein eigener Unterordner angelegt.

Wichtig: Ob Kidney im Master Kontext oder im Ticket Kontext arbeitet, hängt vom aktuellen Arbeitsverzeichnis ab. Befehle aus einem Ticketordner heraus verhalten sich anders als Befehle aus dem Projekt- oder Masterordner.

---

## 6. Ticket anlegen mit `kidney_core create ticket <Name>`

Für jede Aufgabe, jedes Feature oder jeden Bug legst du einen eigenen Ticketordner an.

Beispiel:

```bash
kidney_core create ticket PROJ-123 -m 'Login vereinfachen'
```

- `<Name>` ist typischerweise eine Ticket ID aus deinem Tracker, zum Beispiel `PROJ-123`.
- Mit `-m` oder `--message` kannst du optional eine kurze Beschreibung speichern.

Was passiert?

- Unter `tickets/PROJ-123/` wird ein neuer Ordner angelegt.
- Darin wird eine Datei `.ticket` mit der Ticket ID und der Beschreibung im JSON Format gespeichert.

Empfohlener nächster Schritt:

```bash
cd tickets/PROJ-123
```

Ab jetzt arbeitest du in diesem Ticketordner weiter.

---

## 7. Repositories zum Ticket hinzufügen mit `kidney_core add <repo1> <repo2> ...`

Befindest du dich im Ticketordner (zum Beispiel `tickets/PROJ-123`), verhält sich `kidney_core add` anders als im Master Workspace:

```bash
cd tickets/PROJ-123
kidney_core add app_core ui_core
```

### 7.1 Vereinfachte Angabe der Repositories

Wenn die Repositories bereits in `.master` vorhanden sind, reicht es im Ticketkontext aus, nur die Reponamen anzugeben:

- `kidney_core add app_core ui_core`

Kidney

- kopiert die Repositories aus `.master` in den Ticketordner,
- legt für jedes kopierte Repository einen Branch mit dem Ticketnamen an (hier `PROJ-123`),
- führt in jedem Repository `dart pub get` aus, sofern eine `pubspec.yaml` vorhanden ist.

### 7.2 Automatische Berücksichtigung von Abhängigkeiten

Kidney analysiert die Abhängigkeiten deiner Repositories im Master Workspace und betrachtet

- die Repositories, die du im Ticket mit `add` angibst, und
- die Repositories, die bereits im Ticketordner liegen,

als Endpunkte im Abhängigkeitsgraphen.

Für alle Repositories, die auf dem Weg zwischen diesen Endpunkten liegen, kopiert Kidney automatisch weitere benötigte Repositories in das Ticket. So erhältst du einen möglichst vollständigen Satz an Repositories für dieses Ticket.

### 7.3 Automatische Relokalisierung im Ticket

Nach dem Kopieren aller benötigten Repositories führt Kidney im Ticket eine zweistufige Relokalisierung durch:

1. Unlocalize Schritt
   - Für jedes Repository im Ticket wird geprüft, ob eine Backup Datei `.gg_localize_refs_backup.json` existiert.
   - Falls ja, werden vorherige Lokalisierungsänderungen mit Hilfe von `gg_localize_refs` zurückgenommen.

2. Localize Schritt
   - Alle Repositories im Ticket werden erneut lokalisiert.
   - Abhängigkeiten in `pubspec.yaml` werden so angepasst, dass sie auf die Ticketversionen der Repositories zeigen.
   - Kidney setzt pro Repository den internen Status auf `localized`.
   - Wenn eine `pubspec.yaml` vorhanden ist, wird `dart pub upgrade` ausgeführt.
   - Anschließend wird mit `gg do commit` ein Commit mit einer Standardnachricht erzeugt.

Ergebnis: Alle Repositories im Ticket sind konsistent lokalisiert und können direkt in der Ticketumgebung entwickelt und getestet werden.

---

## 8. Ticket in VS Code öffnen mit `kidney_core code`

Im Ticketordner kannst du mit einem einzelnen Befehl alle Repositories des Tickets in Visual Studio Code öffnen:

```bash
cd tickets/PROJ-123
kidney_core code
```

Was passiert?

- Kidney erkennt automatisch, dass du dich in einem Ticket befindest.
- Für jedes Repository wird `code <pfad>` aufgerufen.

Voraussetzung ist, dass das VS Code Kommando `code` auf deinem System installiert und im `PATH` verfügbar ist.

### 8.1 Einzelne Repositories öffnen

Optional kannst du auch gezielt ein einzelnes Repository öffnen, zum Beispiel aus einem beliebigen Ordner heraus:

```bash
kidney_core code PROJ-123/app_core
```

In der Praxis reicht häufig der einfache Aufruf `kidney_core code` aus dem Ticketordner.

---

## 9. Review mit `kidney_core do review`

Bevor Änderungen aus einem Ticket in zentrale Branches gemergt oder veröffentlicht werden, solltest du einen konsistenten technischen Zustand herstellen. Dafür dient `kidney_core do review`.

### 9.1 Vorbereitung: `kidney_core can review`

Der Befehl `kidney_core do review` ruft intern zunächst `kidney_core can review` auf. Diese Prüfung stellt sicher, dass

- alle Repositories im Ticket den Status `localized` haben und
- keine uncommitteten Änderungen vorhanden sind.

Falls diese Vorbedingungen nicht erfüllt sind, bricht der Reviewprozess ab und du siehst entsprechende Hinweise in der Konsole.

### 9.2 Ablauf von `kidney_core do review`

Führe den Befehl im Ticketordner aus:

```bash
cd tickets/PROJ-123
kidney_core do review
```

Für jedes Repository im Ticket führt Kidney dann im Wesentlichen folgende Schritte aus:

1. Unlocalize
   - Referenzen werden mithilfe von `gg_localize_refs` wieder von lokalen Pfaden auf ihre ursprünglichen Formen zurückgeführt.
   - Der interne Status wird auf `unlocalized` gesetzt.

2. Localize mit Git Referenzen
   - Referenzen werden erneut lokalisiert, diesmal so, dass sie auf Git Referenzen zeigen.
   - Der Status wird auf `git-localized` gesetzt.

3. Abhängigkeiten aktualisieren
   - Wenn `pubspec.yaml` vorhanden ist, wird `dart pub upgrade` ausgeführt.

4. Commit und Push
   - Kidney führt automatisiert `gg do commit` mit einer Standardnachricht aus.
   - Anschließend wird `gg do push` aufgerufen, um die Änderungen zu pushen.

Wenn alle Repositories erfolgreich durchlaufen wurden, ist das Ticket technisch für weitere Schritte wie Merge oder Publish vorbereitet.

Hinweis: Es gibt ergänzende Befehle wie `kidney_core can publish` und `kidney_core do publish`, mit denen du Veröffentlichungsprozesse für alle Repositories eines Tickets steuern kannst. Für einen schnellen Einstieg genügt es jedoch, zunächst mit `do review` zu arbeiten.

---

## 10. Empfohlener Minimal Workflow im Alltag

Zum Abschluss eine kompakte Übersicht über einen typischen Alltagseinsatz.

### 10.1 Einmalig pro Projekt

1. Projektordner anlegen und Workspace initialisieren

   ```bash
   mkdir mein_projekt
   cd mein_projekt
   kidney_core init
   ```

2. Repositories der Organisation in den Master Workspace holen

   ```bash
   kidney_core add https://github.com/meine-org
   ```

### 10.2 Für jedes neue Ticket

1. Ticket anlegen

   ```bash
   cd mein_projekt
   kidney_core create ticket PROJ-123 -m 'Login vereinfachen'
   ```

2. In den Ticketordner wechseln

   ```bash
   cd tickets/PROJ-123
   ```

3. Repositories zum Ticket hinzufügen

   ```bash
   kidney_core add app_core ui_core
   ```

4. Ticket in VS Code öffnen

   ```bash
   kidney_core code
   ```

5. Entwickeln, testen, lokale Commits in den Ticket Repositories ausführen

6. Vor der Freigabe Review durchführen

   ```bash
   kidney_core do review
   ```

Weitere Befehle und Optionen kannst du dir jederzeit über die integrierte Hilfe anzeigen lassen:

```bash
kidney_core -h
kidney_core add -h
kidney_core create -h
kidney_core do -h
kidney_core can -h
```

Mit diesem Workflow solltest du Kidney schnell und produktiv in deinem Dart oder Flutter Multi Repo Projekt einsetzen können.
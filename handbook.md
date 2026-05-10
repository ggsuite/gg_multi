# Gg Multi Handbuch

Praktische Kurzbeschreibung für den täglichen Einsatz von Gg Multi in Dart- und Flutter-Projekten.

Gg Multi unterstützt dich dabei, Multi Repo Projekte mit vielen Git Repositories konsistent zu verwalten. Gg Multi unterstützt derzeit nur Dart / Flutter.

---

## 1. Überblick und Installation

### 1.1 Was ist Gg Multi

Gg Multi ist ein Kommandozeilenwerkzeug für Multi Repo Projekte. Es hilft dir dabei

- alle Repositories eines Projekts zentral zu verwalten,
- pro Ticket eigene Arbeitskopien dieser Repositories anzulegen und
- Abhängigkeiten zwischen Repositories konsistent zu halten.

Wichtiger Unterschied zu **gg**:

- **gg** arbeitet immer in genau einem Git-Repository (z. B. `gg can commit`, `gg do commit`, `gg do push`).
- **gg_multi** baut darauf auf und führt dieselben Arten von Aktionen **repoübergreifend für alle Repositories eines Tickets** aus (z. B. `gg_multi can commit`, `gg_multi do commit`, `gg_multi do push`).

Du verwendest also gg für die Feinarbeit in einem einzelnen Repo und Gg Multi, sobald du mehrere Repos gemeinsam für ein Ticket steuern möchtest.

### 1.2 Voraussetzungen

Bevor du Gg Multi installierst, benötigst du

- Git
- Dart SDK (damit der Befehl `dart` verfügbar ist)
- optional Visual Studio Code inklusive `code` Kommando in deinem `PATH`

### 1.3 Installation

1. Repository klonen

   ```bash
   git clone https://github.com/ggsuite/gg_multi.git
   cd gg_multi
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
   gg_multi -h
   ```

Wenn die Hilfe angezeigt wird, ist Gg Multi einsatzbereit. Alle Beispiele in diesem Handbuch nutzen das Kommando `gg_multi`.

---

## 2. Arbeitsordner für Gg Multi anlegen

Für jedes Multi Repo Projekt solltest du einen eigenen, leeren Projektordner anlegen. In diesem Ordner verwaltet Gg Multi alle Repositories und Tickets.

Beispiel:

```bash
mkdir mein_projekt
cd mein_projekt
```

Alle folgenden Befehle in diesem Handbuch werden von diesem Projektordner oder dessen Unterordnern aus ausgeführt.

---

## 3. Workspace initialisieren mit `gg_multi init`

Im frisch angelegten, leeren Projektordner initialisierst du den Gg Multi Workspace:

```bash
gg_multi init
```

Was passiert dabei?

- Gg Multi prüft, ob der Ordner leer ist und nicht bereits innerhalb eines anderen Gg Multi Workspaces liegt.
- Es wird ein Unterordner `.master` angelegt. Dieser stellt den Master Workspace dar und enthält später die zentralen Klone deiner Repositories.

Ab jetzt erkennt Gg Multi deinen Workspace automatisch, wenn du Befehle irgendwo innerhalb dieses Projektordners ausführst.

---

## 4. Repositories zum Master Workspace hinzufügen

### 4.1 `gg_multi add <group_url>`

Mit `gg_multi add` fügst du Repositories in den Master Workspace unter `.master` hinzu.

Ein typischer erster Schritt ist das Hinzufügen aller Repositories einer Organisation oder Gruppe.

Beispiele für `group_url`:

- GitHub Organisation
  - `https://github.com/meine-org`
- Azure DevOps Organisation und Projekt
  - `https://dev.azure.com/meine-org/mein-projekt`
  - oder die entsprechende SSH Form `git@ssh.dev.azure.com:v3/meine-org/mein-projekt/mein-repo`

Ausführung im Projektordner:

```bash
gg_multi add https://github.com/meine-org
```

Was passiert?

- Gg Multi erkennt, dass es sich um eine Organisations- oder Projektadresse handelt.
- Alle Repositories dieser Gruppe werden in `.master` geklont.

### 4.2 Einzelne Repositories hinzufügen

Du kannst auch einzelne Repositories in `.master` hinzufügen:

- vollständige Git URL (https oder ssh), zum Beispiel
  - `gg_multi add https://github.com/meine-org/app_core.git`
- Kurzform `benutzername/repo`
  - `gg_multi add meine-org/app_core`
- nur der Reponame
  - `gg_multi add app_core`
  - in diesem Fall nutzt Gg Multi Konventionen (zum Beispiel `https://github.com/app_core/app_core.git`) und versucht zusätzlich bekannte Organisationen aus deinem Workspace.

### 4.3 Verhalten bei bereits vorhandenen Repositories

Wenn ein Repository im Master Workspace bereits existiert und nicht leer ist, wird es standardmäßig nicht überschrieben. Gg Multi protokolliert dann nur, dass das Repository schon vorhanden ist.

Mit der Option `--force` kannst du das Repository im Master Workspace trotzdem neu klonen:

```bash
gg_multi add --force https://github.com/meine-org/app_core.git
```

Nutze `--force` nur, wenn du sicher bist, dass du den bestehenden Klon ersetzen möchtest.

---

## 5. Ordnerstruktur verstehen (`.master` und `tickets`)

Nach `gg_multi init` und den ersten `add` Befehlen sieht eine typische Struktur so aus:

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

Wichtig: Ob Gg Multi im Master Kontext oder im Ticket Kontext arbeitet, hängt vom aktuellen Arbeitsverzeichnis ab. Befehle aus einem Ticketordner heraus verhalten sich anders als Befehle aus dem Projekt- oder Masterordner.

---

## 6. Ticket anlegen mit `gg_multi create ticket <Name>`

Für jede Aufgabe, jedes Feature oder jeden Bug legst du einen eigenen Ticketordner an.

Beispiel:

```bash
gg_multi create ticket PROJ-123 -m 'Login vereinfachen'
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

## 7. Repositories zum Ticket hinzufügen mit `gg_multi add <repo1> <repo2> ...`

Befindest du dich im Ticketordner (zum Beispiel `tickets/PROJ-123`), verhält sich `gg_multi add` anders als im Master Workspace:

```bash
cd tickets/PROJ-123
gg_multi add app_core ui_core
```

### 7.1 Vereinfachte Angabe der Repositories

Wenn die Repositories bereits in `.master` vorhanden sind, reicht es im Ticketkontext aus, nur die Reponamen anzugeben:

- `gg_multi add app_core ui_core`

Gg Multi

- kopiert die Repositories aus `.master` in den Ticketordner,
- legt für jedes kopierte Repository einen Branch mit dem Ticketnamen an (hier `PROJ-123`),
- führt in jedem Repository `dart pub get` aus, sofern eine `pubspec.yaml` vorhanden ist.

### 7.2 Automatische Berücksichtigung von Abhängigkeiten

Gg Multi analysiert die Abhängigkeiten deiner Repositories im Master Workspace und betrachtet

- die Repositories, die du im Ticket mit `add` angibst, und
- die Repositories, die bereits im Ticketordner liegen,

als Endpunkte im Abhängigkeitsgraphen.

Für alle Repositories, die auf dem Weg zwischen diesen Endpunkten liegen, kopiert Gg Multi automatisch weitere benötigte Repositories in das Ticket. So erhältst du einen möglichst vollständigen Satz an Repositories für dieses Ticket.

### 7.3 Automatische Relokalisierung im Ticket

Nach dem Kopieren aller benötigten Repositories führt Gg Multi im Ticket eine zweistufige Relokalisierung durch:

1. Unlocalize Schritt
   - Für jedes Repository im Ticket wird geprüft, ob eine Backup Datei `.gg_localize_refs_backup.json` existiert.
   - Falls ja, werden vorherige Lokalisierungsänderungen mit Hilfe von `gg_localize_refs` zurückgenommen.

2. Localize Schritt
   - Alle Repositories im Ticket werden erneut lokalisiert.
   - Abhängigkeiten in `pubspec.yaml` werden so angepasst, dass sie auf die Ticketversionen der Repositories zeigen.
   - Gg Multi setzt pro Repository den internen Status auf `localized`.
   - Wenn eine `pubspec.yaml` vorhanden ist, wird `dart pub upgrade` ausgeführt.
   - Anschließend wird mit `gg do commit` ein Commit mit einer Standardnachricht erzeugt.

Ergebnis: Alle Repositories im Ticket sind konsistent lokalisiert und können direkt in der Ticketumgebung entwickelt und getestet werden.

---

## 8. Ticket in VS Code öffnen mit `gg_multi code`

Im Ticketordner kannst du mit einem einzelnen Befehl alle Repositories des Tickets in Visual Studio Code öffnen:

```bash
cd tickets/PROJ-123
gg_multi code
```

Was passiert?

- Gg Multi erkennt automatisch, dass du dich in einem Ticket befindest.
- Für jedes Repository wird `code <pfad>` aufgerufen.

Voraussetzung ist, dass das VS Code Kommando `code` auf deinem System installiert und im `PATH` verfügbar ist.

### 8.1 Einzelne Repositories öffnen

Optional kannst du auch gezielt ein einzelnes Repository öffnen, zum Beispiel aus einem beliebigen Ordner heraus:

```bash
gg_multi code PROJ-123/app_core
```

In der Praxis reicht häufig der einfache Aufruf `gg_multi code` aus dem Ticketordner.

---

## 9. Commits und Pushes mit `gg_multi can/do commit` und `gg_multi do push`

Bevor du Reviews oder Publishes über alle Ticket-Repositories hinweg ausführst, ist es hilfreich, Commits und Pushes ebenfalls zentral über Gg Multi zu steuern.

Typischerweise arbeitest du dabei im Ticketordner (z. B. `tickets/PROJ-123`).

### 9.1 Prüfen, ob Commits möglich sind: `gg_multi can commit`

Mit

```bash
cd tickets/PROJ-123
gg_multi can commit
```

prüfst du, ob in **allen Repositories des Tickets** Commits möglich sind. Gg Multi

- sucht alle Repositories des Tickets,
- ruft für jedes Repo intern `gg can commit` auf und
- bricht ab, sobald ein Repository nicht commitbar ist.

Damit erkennst du früh, ob z. B. fehlende `pub get`, offene Merge-Konflikte, Test-Fails oder andere Probleme Commits verhindern.

### 9.2 Änderungen committen: `gg_multi do commit`

Mit

```bash
cd tickets/PROJ-123
gg_multi do commit -m "Kurzbeschreibung der Änderung"
```

lässt du Gg Multi in **allen Ticket-Repositories** einen Commit ausführen.

Was passiert dabei grob?

- Gg Multi bestimmt alle Repositories im Ticket (in einer sinnvollen Reihenfolge).
- Für jedes Repo wird intern `gg do commit` mit deiner Commit-Message aufgerufen.
- Falls in einem Repository kein Commit möglich ist, oder keine Änderungen zum committen vorhanden sind, wird dieses Repo übersprungen bzw. ein Fehler protokolliert.

So kannst du mit einem Befehl alle relevanten Repositories eines Tickets konsistent mit der gleichen commit-Message committen, statt in jedem Repo einzeln `gg do commit` auszuführen.

### 9.3 Prüfen und ausführen von Pushes: `gg_multi can push` und `gg_multi do push`

Analog zu `can/do commit` gibt es im Ticketkontext auch `can push` und `do push`:

```bash
cd tickets/PROJ-123
gg_multi can push
gg_multi do push
```

- `gg_multi can push` prüft für alle Ticket-Repos, ob ein Push möglich ist, und ruft dafür intern `gg can push` auf.
- `gg_multi do push` führt anschließend über alle Repositories hinweg `gg do push` aus (optional mit `--force`), sodass alle Ticket-Branches konsistent zum Remote gepusht werden.

Auf diese Weise steuerst du Commits und Pushes für ein komplettes Ticket zentral, während gg weiterhin für die Detailarbeit in einzelnen Repositories zuständig bleibt.

---

## 10. Review mit `gg_multi do review`

Bevor Änderungen aus einem Ticket in zentrale Branches gemergt oder veröffentlicht werden, solltest du einen konsistenten technischen Zustand herstellen. Dafür dient `gg_multi do review`.

### 10.1 Vorbereitung: `gg_multi can review`

Der Befehl `gg_multi do review` ruft intern zunächst `gg_multi can review` auf. Diese Prüfung stellt sicher, dass

- alle Repositories im Ticket den Status `localized` haben und
- keine uncommitteten Änderungen vorhanden sind.

Falls diese Vorbedingungen nicht erfüllt sind, bricht der Reviewprozess ab und du siehst entsprechende Hinweise in der Konsole.

### 10.2 Ablauf von `gg_multi do review`

Führe den Befehl im Ticketordner aus:

```bash
cd tickets/PROJ-123
gg_multi do review
```

Für jedes Repository im Ticket führt Gg Multi dann im Wesentlichen folgende Schritte aus:

1. Unlocalize
   - Referenzen werden mithilfe von `gg_localize_refs` wieder von lokalen Pfaden auf ihre ursprünglichen Formen zurückgeführt.
   - Der interne Status wird auf `unlocalized` gesetzt.

2. Localize mit Git Referenzen
   - Referenzen werden erneut lokalisiert, diesmal so, dass sie auf Git Referenzen zeigen.
   - Der Status wird auf `git-localized` gesetzt.

3. Abhängigkeiten aktualisieren
   - Wenn `pubspec.yaml` vorhanden ist, wird `dart pub upgrade` ausgeführt.

4. Commit und Push
   - Gg Multi führt automatisiert `gg do commit` mit einer Standardnachricht aus.
   - Anschließend wird `gg do push` aufgerufen, um die Änderungen zu pushen.

Wenn alle Repositories erfolgreich durchlaufen wurden, ist das Ticket technisch für weitere Schritte wie Merge oder Publish vorbereitet.

Hinweis: Es gibt ergänzende Befehle wie `gg_multi can publish` und `gg_multi do publish`, mit denen du Veröffentlichungsprozesse für alle Repositories eines Tickets steuern kannst. Für einen schnellen Einstieg genügt es jedoch, zunächst mit `do review` zu arbeiten.

---

## 11. Empfohlener Minimal Workflow im Alltag

Zum Abschluss eine kompakte Übersicht über einen typischen Alltagseinsatz.

### 11.1 Einmalig pro Projekt

1. Projektordner anlegen und Workspace initialisieren

   ```bash
   mkdir mein_projekt
   cd mein_projekt
   gg_multi init
   ```

2. Repositories der Organisation in den Master Workspace holen

   ```bash
   gg_multi add https://github.com/meine-org
   ```

### 11.2 Für jedes neue Ticket

1. Ticket anlegen

   ```bash
   cd mein_projekt
   gg_multi create ticket PROJ-123 -m 'Login vereinfachen'
   ```

2. In den Ticketordner wechseln

   ```bash
   cd tickets/PROJ-123
   ```

3. Repositories zum Ticket hinzufügen

   ```bash
   gg_multi add app_core ui_core
   ```

4. Ticket in VS Code öffnen

   ```bash
   gg_multi code
   ```

5. Entwickeln, testen, lokale Commits in den Ticket Repositories ausführen

6. Vor der Freigabe Review durchführen

   ```bash
   gg_multi do review
   ```

Weitere Befehle und Optionen kannst du dir jederzeit über die integrierte Hilfe anzeigen lassen:

```bash
gg_multi -h
gg_multi add -h
gg_multi create -h
gg_multi do -h
gg_multi can -h
```

Mit diesem Workflow solltest du Gg Multi schnell und produktiv in deinem Dart oder Flutter Multi Repo Projekt einsetzen können.

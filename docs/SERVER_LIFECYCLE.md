# Was passiert, wenn der Server offline geht oder neu installiert wird?

Hier ist die genaue Übersicht, wie sich CrossDrop in verschiedenen Betriebs-Szenarien verhält und wie Sie Ihre Daten sichern.

---

## Szenario 1: Der Server geht vorübergehend offline
*(z. B. Server-Neustart, Wartungsarbeiten oder Internetausfall am Server)*

### Was funktioniert weiterhin?
- **Lokale Dateiübertragungen (LAN / WLAN):**
  Wenn sich Ihre Geräte (PC, Laptop, Handy) im selben Heim- oder Firmennetzwerk befinden, **können Sie weiterhin problemlos Dateien übertragen!**
  Die Direktübertragung läuft direkt von Gerät zu Gerät (Peer-to-Peer auf Port `52520`) und benötigt den Server für den Datentransfer selbst nicht.
- **Transfers brechen nicht ab:** Bereits laufende Übertragungen laufen mit voller Geschwindigkeit weiter.

### Was funktioniert temporär nicht?
- **VPN von unterwegs:** Geräte, die sich nicht im selben WLAN befinden (z. B. unterwegs im Mobilfunknetz), können sich während des Server-Ausfalls nicht über den VPN-Tunnel verbinden.
- **Neue Geräte registrieren:** Ein neues Gerät kann erst wieder hinzugefügt werden, wenn der Server erreichbar ist.

### Sobald der Server wieder online ist:
- **100% Automatischer Reconnect:** Sie müssen die App **nicht** neu starten. Der Hintergrund-Timer und der VPN-Dienst erkennen automatisch, dass der Server wieder da ist, und verbinden sich innerhalb von Sekunden neu!

---

## Szenario 2: Server-Neustart oder Docker-Update (`docker compose up -d`)
*(z. B. wenn Sie den Server aktualisieren oder den Container neu starten)*

- **KEIN DATENVERLUST!**
- Die gesamte Datenbank liegt dank des Docker-Volumes im Ordner `./data/crossdrop.db` auf der echten Festplatte Ihres Linux-Servers (nicht nur im flüchtigen Container).
- Alle registrierten Accounts, Passwörter und Geräte bleiben nach dem Neustart vollständig erhalten.
- Niemand muss sich neu anmelden.

---

## Szenario 3: Der Linux-Server wird komplett neu installiert

### Option A: Mit Backup (Empfohlen – Dauert 5 Sekunden!)

Sie müssen lediglich eine einzige Datei sichern:
1. **Vor der Neuinstallation sichern:**
   Kopieren Sie die Datei `crossdrop.db` aus dem Server-Ordner:
   ```bash
   cp /opt/crossdrop-server/data/crossdrop.db /mein-backup-pfad/
   ```
2. **Nach der Linux-Neuinstallation wiederherstellen:**
   Kopieren Sie den Ordner `server/` wieder auf den neuen Server, legen Sie die gesicherte `crossdrop.db` in den Ordner `data/` und starten Sie Docker:
   ```bash
   mkdir -p /opt/crossdrop-server/data
   cp /mein-backup-pfad/crossdrop.db /opt/crossdrop-server/data/
   docker compose up -d --build
   ```
3. **Ergebnis:** Alle Konten, Geräte und Einstellungen sind sofort wieder 1:1 da!

---

### Option B: Ohne Backup (Server wird komplett frisch aufgesetzt)

Falls die Datenbank gelöscht wurde oder keine Sicherung vorliegt:
1. Der neue Server startet mit einer frischen, leeren Datenbank.
2. Wenn ein Client (PC oder Smartphone) versucht, sich mit dem alten Token zu verbinden, meldet der Server `401 Unauthorized` (Konto nicht gefunden).
3. **Die App stürzt nicht ab**, sondern fängt dies sauber ab:
   - Die App meldet sich ab und zeigt: *„Der Server wurde neu aufgesetzt oder die Sitzung ist abgelaufen.“*
   - Die Nutzer tippen einfach auf **„Konto erstellen“** und registrieren sich mit E-Mail und Passwort in 10 Sekunden neu.
   - Die Geräte verbinden sich wieder automatisch mit dem neuen Konto.

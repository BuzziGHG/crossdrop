# CrossDrop 🚀

> **Schneller, sicherer und unkomplizierter Datentransfer zwischen Windows, Linux und Android.**  
> Übertragen Sie Dateien und Ordner jeder Größe blitzschnell im lokalen Netzwerk (LAN / WLAN) oder automatisch über den integrierten VPN-Tunnel von überall auf der Welt.

---

## 📥 Downloads (Aktuelle Version 1.0.0)

Wählen Sie einfach Ihr Betriebssystem aus und laden Sie die passende Version herunter:

| Plattform | Dateityp | Download-Link |
| :--- | :--- | :--- |
| 🪟 **Windows 10 / 11** | Portable ZIP (`.exe`) | [⬇️ CrossDrop-Windows-x64.zip](https://github.com/BuzziGHG/crossdrop/releases/latest/download/CrossDrop-Windows-x64.zip) |
| 🐧 **Linux (Debian / Ubuntu)** | Paket (`.deb`) | [⬇️ crossdrop_1.0.0_amd64.deb](https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop_1.0.0_amd64.deb) |
| 📱 **Android** | App-Paket (`.apk`) | [⬇️ crossdrop-release.apk](https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop-release.apk) |

👉 **[Alle Downloads und Versionshinweise auf der Release-Seite ansehen](https://github.com/BuzziGHG/crossdrop/releases)**

---

## ⚡ Schnellstart: In 3 Schritten zur ersten Dateiübertragung

### 1. App installieren & starten
- **Windows:** ZIP entpacken und `crossdrop.exe` starten.
- **Linux:** Paket per Doppelklick oder mit `sudo dpkg -i crossdrop_1.0.0_amd64.deb` installieren.
- **Android:** Die `.apk` auf das Smartphone laden und antippen (Installation aus Drittquellen erlauben).

### 2. Kostenlosen Account erstellen & anmelden
- Beim ersten Start auf **„Noch kein Konto? Hier registrieren“** tippen.
- E-Mail-Adresse, Benutzernamen und ein persönliches Passwort eingeben.
- *(Die Server-Adresse `http://82.29.5.240:2603` ist in der App bereits standardmäßig voreingestellt – Sie müssen nichts manuell konfigurieren!)*

### 3. Dateien senden
- Wählen Sie im Menü **„Dateien senden“** beliebige Dateien oder Dokumente aus.
- Wählen Sie Ihr gewünschtes Zielgerät aus der Liste.
- Bestätigen Sie die Übertragung auf dem Empfängergerät – fertig!

---

## ✨ Features auf einen Blick

- 🏎️ **Kein Größenlimit:** Senden Sie kleine Fotos oder gigantische 100 GB Videos ohne künstliche Drosselung.
- 🔒 **Zero-Config VPN:** Wenn Sie nicht im selben WLAN sind, schaltet CrossDrop automatisch auf den verschlüsselten VPN-Tunnel um. Keine Router-Ports müssen freigegeben werden.
- 🛡️ **SHA-256 Integritätsprüfung:** Jede übertragene Datei wird kryptografisch geprüft, um Fehler und Beschädigungen auszuschließen.
- 👥 **Geräte-Erkennung:** Sobald Ihre Geräte online sind, erscheinen sie sofort in der Auswahlliste.

---

<details>
<summary>🛠️ Für Administratoren: Eigenen Server einrichten (IP: 82.29.5.240 / Port: 2603)</summary>

<br>

Falls Sie den zentralen Account- und VPN-Tunnel-Server auf Ihrem eigenen Linux-Server betreiben oder verwalten möchten:

### 1. Docker auf dem Server installieren:
```bash
sudo apt update && sudo apt install -y git docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

### 2. Server starten (Port 2603):
```bash
git clone https://github.com/BuzziGHG/crossdrop.git /opt/crossdrop
cd /opt/crossdrop/server
docker compose up -d --build
```

### 3. Firewall freigeben:
```bash
sudo ufw allow 2603/tcp
sudo ufw reload
```

- **Health-Check:** `curl http://82.29.5.240:2603/health`
- **Swagger-Dokumentation:** `http://82.29.5.240:2603/docs`
- Ausführliche Dokumentation: siehe [`docs/SERVER_SETUP.md`](docs/SERVER_SETUP.md).

</details>

---

## Lizenz
Entwickelt mit Flutter und FastAPI. Open Source lizenziert unter der MIT-Lizenz.

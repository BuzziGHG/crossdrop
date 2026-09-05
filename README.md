# CrossDrop 🚀

[![Release](https://img.shields.io/github/v/release/BuzziGHG/crossdrop?color=blue&label=Aktuelle%20Version)](https://github.com/BuzziGHG/crossdrop/releases/latest)
[![Plattformen](https://img.shields.io/badge/Plattformen-Windows%20%7C%20Linux%20%7C%20Android-brightgreen)](#-downloads-aktuelle-version-130)
[![Lizenz](https://img.shields.io/badge/Lizenz-MIT-orange)](LICENSE)

> **Schneller, sicherer und grenzenloser Datentransfer zwischen Windows, Linux und Android.**  
> Übertragen Sie Dateien und Ordner jeder Größe blitzschnell im lokalen Netzwerk (LAN / WLAN) oder automatisch über den integrierten VPN-Tunnel und das Zero-Disk Streaming-Relay – weltweit und ohne Router-Konfiguration.

---

## 📥 Downloads (Aktuelle Version 1.3.1)

Wählen Sie einfach Ihr Betriebssystem aus und laden Sie die passende Version herunter:

| Plattform | Dateityp | GitHub-Download | Schneller Server-Spiegel |
| :--- | :--- | :--- | :--- |
| 🪟 **Windows 10 / 11** | Setup-Installer (`.exe`) | [⬇️ CrossDrop-Windows-Setup.exe](https://github.com/BuzziGHG/crossdrop/releases/latest/download/CrossDrop-Windows-Setup.exe) *(Empfohlen)* | [⚡ Direktdownload](http://82.29.5.240:2603/api/updates/download/windows) |
| 🪟 **Windows (Portabel)** | ZIP-Archiv | [⬇️ CrossDrop-Windows-x64.zip](https://github.com/BuzziGHG/crossdrop/releases/latest/download/CrossDrop-Windows-x64.zip) | - |
| 🐧 **Linux (Debian / Ubuntu)** | Paket (`.deb`) | [⬇️ crossdrop_1.3.1_amd64.deb](https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop_1.3.1_amd64.deb) | [⚡ Direktdownload](http://82.29.5.240:2603/api/updates/download/linux) |
| 📱 **Android** | App-Paket (`.apk`) | [⬇️ crossdrop-release.apk](https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop-release.apk) | [⚡ Direktdownload](http://82.29.5.240:2603/api/updates/download/android) |

👉 **[Alle Downloads und Versionshinweise auf der Release-Seite ansehen](https://github.com/BuzziGHG/crossdrop/releases)**

---

## ✨ Was ist neu in Version 1.3.1?

- 📱 **Android In-App Update & Paket-Installer behoben:**
  - Natives Android `FileProvider` (`filepaths.xml`) für sichere Installation aus dem öffentlichen Downloads-Ordner konfiguriert.
  - Eigener nativer MethodChannel zur zuverlässigen Übergabe an den Android-System-Installer (`ACTION_VIEW`).
  - Automatisches Öffnen der Systemeinstellungen für *"Unbekannte Apps installieren"*, falls die Berechtigung noch nicht erteilt wurde.
  - Das Update-Fenster bleibt nach dem 100%-Download geöffnet und bietet nun klare Buttons: **[ Jetzt installieren ]** und **[ Berechtigung prüfen ]**.
- 💾 **Zero-Disk In-Memory Streaming Relay:**
  Dateien werden nicht mehr auf der Festplatte des Servers zwischengespeichert! Der Server fungiert als reine In-Memory Pipeline (`RelayPipe` mit ~1 MB Puffer). Selbst Dateien mit 100 GB oder mehr verbrauchen **0 Byte Server-Festplatte** und überlasten niemals den Speicher.
- 📊 **100 % synchrone Live-Fortschrittsanzeige:**
  Sender und Empfänger sind gleichzeitig verbunden. Beide Fortschrittsbalken laufen in Echtzeit absolut synchron von **0 % bis 100 %** mit exakt identischer Geschwindigkeit und Restzeit (ETA).
- 📧 **Cross-Account Transfer via E-Mail:**
  Dateien können direkt an andere registrierte CrossDrop-Accounts gesendet werden. Aus Sicherheitsgründen muss der Empfänger externe Sendungen vor Beginn immer explizit bestätigen.
- ⚡ **Automatisches Auto-Accept für eigene Geräte:**
  Übertragungen zwischen den eigenen registrierten Geräten werden vollautomatisch angenommen – kein lästiges manuelles Bestätigen mehr!
- 🔔 **Hintergrund-Übertragung & Notification-Fortschritt:**
  Übertragungen laufen dank Wakelock zuverlässig im Hintergrund weiter. Auf Android und Desktop informiert ein Live-Fortschrittsbalken direkt in der Benachrichtigungsleiste.
- 🔄 **Integrierter Auto-Updater:**
  Erkennt neue Updates automatisch und ermöglicht die Aktualisierung mit einem Klick direkt aus der App heraus.

---

## ⚡ Schnellstart: In 3 Schritten zur ersten Dateiübertragung

### 1. App installieren & starten
- **Windows:** `CrossDrop-Windows-Setup.exe` ausführen (erstellt automatisch ein Startmenü- und Desktop-Icon).
- **Linux:** Paket per Doppelklick oder mit `sudo dpkg -i crossdrop_1.3.0_amd64.deb` installieren.
- **Android:** `crossdrop-release.apk` herunterladen und antippen (Installation aus vertrauenswürdigen Quellen aktivieren).

### 2. Kostenlosen Account erstellen & anmelden
- Beim ersten Start auf **„Noch kein Konto? Hier registrieren“** tippen.
- E-Mail-Adresse, Benutzernamen und ein persönliches Passwort festlegen.
- *(Die Server-Adresse `http://82.29.5.240:2603` ist in der App bereits vorkonfiguriert – keine manuelle Einrichtung nötig!)*

### 3. Dateien senden
- Wählen Sie im Menü **„Dateien senden“** beliebige Dokumente, Bilder oder Videos aus.
- Wählen Sie Ihr gewünschtes Zielgerät aus der Geräteliste oder geben Sie die E-Mail-Adresse eines Freundes ein.
- Die Übertragung startet sofort mit synchroner Live-Fortschrittsanzeige!

---

## 🛠️ Technische Architektur

CrossDrop kombiniert modernste Übertragungstechnologien für maximale Geschwindigkeit und Sicherheit:

```mermaid
graph TD
    A["Sender: Windows / Linux / Android"] -->|1. Teste lokales Netzwerk| B{"Gleiches LAN/WLAN?"}
    B -->|Ja| C["Direkte P2P Verbindung HTTP/TCP 52520<br>(Volle Gigabit/WLAN Geschwindigkeit)"]
    B -->|Nein / Firewall| D["Zero-Disk Streaming Relay Server<br>(RAM-Pipe ~1 MB Puffer, 0 Bytes Disk)"]
    C --> E["Empfänger: Android / Windows / Linux"]
    D --> E
```

1. **Priorität 1 – Lokales Netzwerk (LAN / WLAN):**
   Direkter Peer-to-Peer Stream über TCP/HTTP Port 52520 mit nativer Netzwerkgeschwindigkeit (ohne Umweg über das Internet).
2. **Priorität 2 – VPN Server-Relay (Zero-Disk):**
   Befinden sich die Geräte in verschiedenen Netzwerken, Mobilfunk oder hinter restriktiven Firewalls, streamt CrossDrop über die integrierte WebSocket- und Streaming-Pipeline im Arbeitsspeicher des Servers.
3. **Sicherheit:**
   Vollständige SHA-256 Integritätsprüfung nach Abschluss jedes Dateitransfers.

---

## 📄 Lizenz

Entwickelt mit Flutter (Frontend) und FastAPI / Python (Backend).  
Open Source lizenziert unter der [MIT-Lizenz](LICENSE).

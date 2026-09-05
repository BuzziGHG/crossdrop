# CrossDrop 🚀
### Plattformübergreifender Datentransfer für Windows 10/11, Debian/Linux & Android

CrossDrop verbindet Ihre PCs und Mobilgeräte über ein selbst gehostetes Account-System und erlaubt blitzschnelle Dateiübertragungen wahlweise über **Lokales Netzwerk (LAN)** oder einen **automatischen Zero-Config VPN-Tunnel**.

---

## Neu in Version 1.0.0

- 👤 **Freie Selbstregistrierung:** Jeder Benutzer kann sich direkt in der App mit eigener E-Mail und individuellem Passwort registrieren.
- 🌐 **Automatischer VPN-Tunnel (Zero-Config):** Sobald Sie sich in der App anmelden, stellt das Gerät **vollautomatisch** eine sichere, verschlüsselte Tunnel-Verbindung zum Linux-Server her. **Keine manuelle Server-Konfiguration, keine Zertifikate und keine Portweiterleitungen am Router nötig!**
- 📦 **Automatischer Cloud-Build via GitHub:** Sie müssen keine Gigabytes an SDKs lokal installieren. Ein Push zu GitHub baut automatisch die fertige **Windows `.exe`**, **Linux `.deb`** und **Android `.apk`** und legt sie unter *Releases* ab!

---

## Schnellstart

1. **Auf GitHub hochladen & fertige Apps herunterladen:**
   - Doppelklick auf `upload_to_github.bat` (oder siehe Anleitung in [docs/GITHUB_UPLOAD.md](docs/GITHUB_UPLOAD.md)).
   - GitHub Actions kompiliert alle 3 Apps und stellt sie unter **Releases** als Download bereit.
2. **Server auf Ihrem Linux-Server starten:**
   ```bash
   cd server
   docker compose up -d --build
   ```
3. **App starten & loslegen:**
   - Server-URL eingeben, Account registrieren.
   - Der VPN-Tunnel verbindet sich sofort automatisch.
   - Dateien mit 1 Klick an Ihre anderen Geräte senden!

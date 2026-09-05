# CrossDrop: Vollständige Anleitung & System-Dokumentation

CrossDrop ist ein plattformübergreifendes System zur sicheren und extrem schnellen Datei- und Datenübertragung zwischen Windows, Linux und Android mit eigenem Benutzer-Account-System.

---

## 1. Übersicht der Komponenten

1. **Linux Server Backend (`server/`):**
   - Verwaltet Benutzerkonten (E-Mail, Passwort per bcrypt gehasht, JWT-Authentifizierung).
   - Registriert verbundene Geräte und überwacht deren Online-Status (Heartbeat alle 15 Sekunden).
   - Tauscht dynamisch die lokalen IP-Adressen (LAN) und VPN-IP-Adressen zwischen Ihren Geräten aus.
   - Läuft in einem Docker-Container auf jedem Linux-Server.

2. **Cross-Platform Client (`client/`):**
   - **Windows 10 & 11:** Kompiliert zu einer nativen `.exe`.
   - **Debian / Ubuntu / Linux:** Kompiliert zu einem nativen Linux-Binary und schnürt ein `.deb` Installationspaket.
   - **Android:** Kompiliert zu einer eigenständigen `.apk`.
   - Eingebetteter Peer-to-Peer Transfer-Server (Port 52520) für direkte Übertragungen ohne Bandbreitenbegrenzung.

---

## 2. Linux Server einrichten (Account-Datenbank & API)

### Schritt 1: Docker auf dem Linux-Server installieren
Falls auf Ihrem Linux-Server (z. B. Debian 11/12 oder Ubuntu 22.04/24.04) noch kein Docker installiert ist:
```bash
sudo apt update
sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

### Schritt 2: Server-Dateien bereitstellen & starten
Kopieren Sie den Ordner `server/` auf Ihren Linux-Server (z. B. nach `/opt/crossdrop`):
```bash
# Auf dem Server:
mkdir -p /opt/crossdrop
cd /opt/crossdrop

# Starten mit Docker Compose:
docker compose up -d --build
```

**Fertig!**
- Die Datenbank (SQLite) wird persistent im Ordner `./data/crossdrop.db` abgelegt.
- Der Server hört standardmäßig auf Port `8000`.
- Unter `http://<SERVER-IP>:2603/docs` können Sie die interaktive Swagger-API-Dokumentation aufrufen und testen.

### Schritt 3: Optional mit Domain & SSL (HTTPS) absichern
Damit Ihre Geräte auch von unterwegs sicher über das Internet mit dem Server kommunizieren können, richten Sie Nginx mit einem kostenlosen Let's Encrypt Zertifikat ein:
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

Nginx Konfiguration `/etc/nginx/sites-available/crossdrop.conf`:
```nginx
server {
    server_name crossdrop.meinedomain.de;

    location / {
        proxy_pass http://127.0.0.1:2603;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 100M;
    }
}
```

Aktivieren und SSL anfordern:
```bash
sudo ln -s /etc/nginx/sites-available/crossdrop.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d crossdrop.meinedomain.de
```

---

## 3. Datenübertragung: Wie funktioniert LAN vs. VPN?

In der App können Sie für jedes Zielgerät auswählen, wie Sie die Daten übertragen möchten:

### Option A: Lokales Netzwerk (LAN / WLAN)
- **Wann nutzen:** Wenn sich beide Geräte im selben WLAN oder Heimnetzwerk befinden (z. B. PC und Smartphone zu Hause).
- **Vorteil:** Maximale Geschwindigkeit (bis zu 100+ MB/s bzw. Gigabit-Wire-Speed), da die Daten direkt von Gerät zu Gerät fließen, ohne das Internet zu belasten.
- **Funktionsweise:** Die App wählt automatisch die lokale IP (z. B. `192.168.1.50`) des Empfängers und baut eine direkte TCP-Stream-Verbindung auf Port `52520` auf.

### Option B: VPN-Verbindung (WireGuard / Tailscale / OpenVPN)
- **Wann nutzen:** Wenn Sie unterwegs sind (z. B. Smartphone im Mobilfunknetz und PC zu Hause).
- **Vorteil:** Ende-zu-Ende verschlüsselte Direktverbindung über Ihr persönliches VPN, ohne Portweiterleitungen am Heim-Router einrichten zu müssen.
- **Funktionsweise:** Die App erkennt automatisch vorhandene VPN-Schnittstellen (wie WireGuard `10.8.0.x` oder Tailscale `100.x.x.x`) und überträgt die Datei direkt über den VPN-Tunnel.

### Sicherheits-Handshake:
Wenn ein Gerät eine Datei senden möchte:
1. Der Sender stellt eine Anfrage mit Dateiname, Größe und Prüfsumme.
2. Auf dem Empfänger-Gerät erscheint ein Dialog:
   *„Gerät 'Mein Laptop' möchte 'Urlaubsvideos.zip' (2.4 GB) senden. [Annehmen / Ablehnen]“*
3. Erst nach Bestätigung beginnt der Transfer (in den Einstellungen kann auch „Automatisch annehmen für eigene Geräte“ aktiviert werden).
4. Nach Abschluss prüft der Empfänger automatisch den SHA-256 Hash.

---

## 4. Wie erhalten Sie die fertigen Builds (.exe, .deb, .apk)?

### Methode 1: Automatischer Cloud-Build via GitHub Actions (Empfohlen - 0 lokale Installationen!)
Im Projekt befindet sich eine fertige GitHub Actions Pipeline (`.github/workflows/build_all.yml`):
1. Erstellen Sie ein neues privates GitHub-Repository.
2. Pushen Sie das `crossdrop`-Projekt in Ihr Repository:
   ```bash
   git init
   git add .
   git commit -m "Initial CrossDrop Commit"
   git remote add origin https://github.com/<IhrName>/crossdrop.git
   git push -u origin main
   ```
3. GitHub Actions baut nun vollautomatisch:
   - **`CrossDrop-Windows-x64.zip`** (enthält die fertige `.exe`)
   - **`crossdrop_1.0.0_amd64.deb`** (fertiges Debian/Linux-Installationspaket)
   - **`crossdrop-release.apk`** (fertige Android APK zum Installieren)
4. Unter dem Reiter **„Actions“** in GitHub können Sie alle drei fertigen Installationsdateien direkt herunterladen!

---

### Methode 2: Lokales Bauen auf Ihrem System

#### 1. Windows 10/11 (.exe):
- Installieren Sie das [Flutter SDK](https://flutter.dev) und Visual Studio (C++ Desktop Tools).
- Führen Sie das Skript aus:
  ```cmd
  build_scripts\build_windows.bat
  ```
- Die fertige `crossdrop.exe` liegt danach in `build_scripts\dist-windows\crossdrop.exe`.

#### 2. Debian / Linux (.deb):
- Führen Sie auf Ihrem Debian/Ubuntu-System aus:
  ```bash
  chmod +x build_scripts/build_linux.sh
  ./build_scripts/build_linux.sh
  ```
- Installieren des fertigen Pakets:
  ```bash
  sudo dpkg -i build_scripts/crossdrop_1.0.0_amd64.deb
  ```

#### 3. Android (.apk):
- Führen Sie aus:
  ```cmd
  build_scripts\build_android.bat
  ```
- Die fertige APK liegt danach in `build_scripts\crossdrop-release.apk`.
- Übertragen Sie die APK auf Ihr Android-Gerät und tippen Sie darauf zum Installieren.

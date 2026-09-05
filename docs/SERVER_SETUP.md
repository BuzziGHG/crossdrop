# CrossDrop: Server-Einrichtung (IP: 82.29.5.240 | Port: 2603)

Diese Schritt-für-Schritt-Anleitung zeigt Ihnen, wie Sie das CrossDrop Backend auf Ihrem Linux-Server (**82.29.5.240**) auf Port **2603** in weniger als 2 Minuten installieren und starten.

---

## Schnellstart: In 4 Befehlen einsatzbereit

Verbinden Sie sich per SSH mit Ihrem Server `82.29.5.240`:
```bash
ssh root@82.29.5.240
```

Führen Sie die folgenden Befehle nacheinander aus:

### 1. Docker & Git installieren (falls noch nicht vorhanden)
```bash
sudo apt update && sudo apt install -y git docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

### 2. CrossDrop herunterladen
```bash
git clone https://github.com/BuzziGHG/crossdrop.git /opt/crossdrop
cd /opt/crossdrop/server
```

### 3. Server starten (Port 2603)
```bash
docker compose up -d --build
```

### 4. Firewall-Port 2603 freigeben (falls UFW aktiv ist)
```bash
sudo ufw allow 2603/tcp
sudo ufw reload
```

---

## Funktionsprüfung

### Im Terminal prüfen:
```bash
# Container-Status ansehen:
docker compose ps

# Live-Logs ansehen:
docker compose logs -f

# Health-Check abfragen:
curl http://82.29.5.240:2603/health
```
Antwort bei Erfolg:
```json
{"status":"ok","version":"1.0.0"}
```

### Im Webbrowser aufrufen:
Öffnen Sie auf Ihrem PC oder Smartphone:
👉 **[http://82.29.5.240:2603/docs](http://82.29.5.240:2603/docs)**

Hier sehen Sie sofort die interaktive Swagger-Dokumentation aller Endpunkte (Registrierung, Login, VPN-Tunneling, Geräteverwaltung).

---

## Was macht der Server?

1. **Benutzer-Datenbank (SQLite):**
   - Befindet sich persistent in `/opt/crossdrop/server/data/crossdrop.db`.
   - Passwörter werden sicher per `bcrypt` gehasht gespeichert.
   - Jeder kann sich direkt in der App registrieren und anmelden.

2. **Automatischer VPN-Tunnel (Zero-Config):**
   - Sobald sich ein Gerät (Windows, Linux, Android) anmeldet, verbindet es sich automatisch über einen sicheren WebSocket-Tunnel mit dem Server (`/api/v1/vpn/tunnel`).
   - Jedes Gerät erhält eine interne IP (`10.42.0.x`), sodass Sie auch von unterwegs ohne manuelle Router-Portfreigaben Dateien übertragen können.

3. **Geräte-Registry & Heartbeat:**
   - Alle 15 Sekunden meldet sich jedes angemeldete Gerät.
   - Wenn Sie die App öffnen, sehen Sie sofort, welche Ihrer anderen Geräte gerade online sind.

---

## Optional: Absicherung mit Domain & SSL (HTTPS / Nginx)

Wenn Sie eine eigene Domain besitzen (z. B. `crossdrop.meinedomain.de`) und Port 443 mit kostenlosem Let's Encrypt SSL nutzen möchten:

### 1. Nginx & Certbot installieren:
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

### 2. Nginx-Konfiguration erstellen (`/etc/nginx/sites-available/crossdrop.conf`):
```nginx
server {
    server_name crossdrop.meinedomain.de;

    location / {
        proxy_pass http://127.0.0.1:2603;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket-Unterstützung für den VPN-Tunnel:
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        client_max_body_size 500M;
    }
}
```

### 3. Aktivieren und Zertifikat erstellen:
```bash
sudo ln -s /etc/nginx/sites-available/crossdrop.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d crossdrop.meinedomain.de
```

Fertig! In der App können Sie dann als Server-URL einfach `https://crossdrop.meinedomain.de` eintragen.

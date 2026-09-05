# CrossDrop Server: Self-Hosted Account & Geräte-Server

Dieser Server verwaltet Benutzerkonten, registrierte Geräte, Online-Status (Heartbeats) und tauscht Netzwerk-Endpunkte (lokale IP-Adressen und VPN-IP-Adressen) zwischen Ihren Geräten aus.

---

## 1. Schnelle Einrichtung mit Docker Compose (Empfohlen)

### Voraussetzungen auf Ihrem Debian / Ubuntu Linux Server:
Installieren Sie Docker und Docker Compose (falls noch nicht vorhanden):
```bash
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker
```

### Server starten:
1. Kopieren Sie den Ordner `server/` auf Ihren Linux-Server (z. B. nach `/opt/crossdrop-server`).
2. Passen Sie bei Bedarf in der `docker-compose.yml` den `JWT_SECRET` an (einen zufälligen sicheren String eingeben).
3. Starten Sie den Container im Hintergrund:
   ```bash
   cd /opt/crossdrop-server
   docker compose up -d --build
   ```
4. Der Server läuft nun auf Port `2603`.
   Überprüfen Sie den Status mit:
   ```bash
   docker compose logs -f
   ```
   Oder im Browser: `http://<IHRE-SERVER-IP>:2603/docs` (Interaktive Swagger-API-Dokumentation).

---

## 2. Einrichtung mit Domain & SSL (HTTPS / Let's Encrypt) mit Nginx

Für maximale Sicherheit (insbesondere bei Zugriff von unterwegs) empfiehlt sich ein Reverse Proxy mit kostenlosem SSL-Zertifikat:

### Nginx installieren:
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

### Nginx Konfiguration erstellen:
Erstellen Sie die Datei `/etc/nginx/sites-available/crossdrop.conf`:
```nginx
server {
    server_name crossdrop.meinedomain.de; # Ersetzen mit Ihrer Domain

    location / {
        proxy_pass http://127.0.0.1:2603;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket & Streaming Support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 500M;
    }
}
```

Aktivieren und SSL-Zertifikat anfordern:
```bash
sudo ln -s /etc/nginx/sites-available/crossdrop.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d crossdrop.meinedomain.de
```

Ihre Server-URL für die App lautet dann:
`https://crossdrop.meinedomain.de`

---

## 3. Firewall (UFW) Hinweise

Falls UFW aktiv ist:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```
Hinweis: Port 52520 (der P2P-Transfer-Port) läuft **direkt auf den Endgeräten** (Windows, Linux, Android) und muss **nicht** auf dem zentralen Server freigegeben werden, es sei denn, der Server dient selbst als Endgerät.

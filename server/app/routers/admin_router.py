import json
import time
from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, Depends
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.database import get_db, User, Device
from app.routers.vpn_router import active_tunnels

router = APIRouter(tags=["Administration Dashboard"])
SERVER_START_TIME = datetime.utcnow()

@router.get("/api/admin/stats")
def get_admin_stats(db: Session = Depends(get_db)) -> Dict[str, Any]:
    users = db.query(User).all()
    devices = db.query(Device).all()

    user_list = []
    for u in users:
        dev_count = len(u.devices) if u.devices else 0
        user_list.append({
            "id": u.id,
            "username": u.username,
            "email": u.email,
            "created_at": u.created_at.strftime("%Y-%m-%d %H:%M:%S") if u.created_at else "N/A",
            "devices_count": dev_count
        })

    device_list = []
    for d in devices:
        try:
            local_ips = json.loads(d.local_ips) if d.local_ips else []
        except Exception:
            local_ips = []

        try:
            vpn_ips = json.loads(d.vpn_ips) if d.vpn_ips else []
        except Exception:
            vpn_ips = []

        is_tunnel_active = d.id in active_tunnels

        device_list.append({
            "id": d.id,
            "name": d.name,
            "platform": d.platform,
            "owner": d.owner.username if d.owner else "Unbekannt",
            "local_ips": local_ips,
            "vpn_ips": vpn_ips,
            "is_online": d.is_online or is_tunnel_active,
            "is_tunnel_active": is_tunnel_active,
            "last_seen": d.last_seen.strftime("%Y-%m-%d %H:%M:%S") if d.last_seen else "N/A"
        })

    uptime_delta = datetime.utcnow() - SERVER_START_TIME
    hours, remainder = divmod(int(uptime_delta.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    uptime_str = f"{hours}h {minutes}m {seconds}s"

    return {
        "status": "online",
        "port": 2603,
        "uptime": uptime_str,
        "server_time": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"),
        "total_users": len(users),
        "total_devices": len(devices),
        "active_vpn_tunnels": len(active_tunnels),
        "users": user_list,
        "devices": device_list
    }

@router.get("/admin", response_class=HTMLResponse)
def admin_dashboard():
    html_content = """<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CrossDrop Server Administration</title>
  <style>
    :root {
      --bg: #0f172a;
      --card-bg: #1e293b;
      --card-border: #334155;
      --text: #f8fafc;
      --text-muted: #94a3b8;
      --primary: #3b82f6;
      --primary-hover: #2563eb;
      --success: #10b981;
      --warning: #f59e0b;
      --danger: #ef4444;
      --badge-bg: #1e3a8a;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    body { background-color: var(--bg); color: var(--text); padding: 24px; min-height: 100vh; }
    .container { max-width: 1200px; margin: 0 auto; }
    header { display: flex; justify-content: space-between; align-items: center; padding-bottom: 24px; border-bottom: 1px solid var(--card-border); margin-bottom: 28px; flex-wrap: wrap; gap: 16px; }
    .logo-area { display: flex; align-items: center; gap: 14px; }
    .logo-icon { width: 44px; height: 44px; background: linear-gradient(135deg, #3b82f6, #06b6d4); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 24px; font-weight: bold; box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4); }
    h1 { font-size: 24px; font-weight: 700; letter-spacing: -0.5px; }
    .subtitle { color: var(--text-muted); font-size: 14px; margin-top: 2px; }
    .status-pill { display: inline-flex; align-items: center; gap: 8px; background: rgba(16, 185, 129, 0.15); border: 1px solid rgba(16, 185, 129, 0.3); color: #34d399; padding: 6px 14px; border-radius: 9999px; font-size: 13px; font-weight: 600; }
    .status-dot { width: 8px; height: 8px; background: #34d399; border-radius: 50%; box-shadow: 0 0 10px #34d399; animation: pulse 2s infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
    .grid-stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 20px; margin-bottom: 32px; }
    .stat-card { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 16px; padding: 22px; display: flex; flex-direction: column; justify-content: space-between; transition: transform 0.2s, border-color 0.2s; }
    .stat-card:hover { transform: translateY(-2px); border-color: var(--primary); }
    .stat-title { font-size: 13px; text-transform: uppercase; letter-spacing: 0.8px; color: var(--text-muted); margin-bottom: 8px; font-weight: 600; }
    .stat-value { font-size: 32px; font-weight: 800; color: #fff; line-height: 1.1; }
    .stat-meta { font-size: 13px; color: var(--text-muted); margin-top: 8px; display: flex; align-items: center; gap: 6px; }
    .card { background: var(--card-bg); border: 1px solid var(--card-border); border-radius: 16px; padding: 24px; margin-bottom: 28px; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); }
    .card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 18px; }
    .card-title { font-size: 18px; font-weight: 700; display: flex; align-items: center; gap: 10px; }
    table { width: 100%; border-collapse: collapse; text-align: left; }
    th { padding: 12px 16px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.6px; color: var(--text-muted); border-bottom: 1px solid var(--card-border); font-weight: 600; }
    td { padding: 14px 16px; font-size: 14px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: rgba(255, 255, 255, 0.02); }
    .badge { display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 6px; font-size: 12px; font-weight: 600; }
    .badge-online { background: rgba(16, 185, 129, 0.2); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); }
    .badge-offline { background: rgba(148, 163, 184, 0.1); color: #94a3b8; border: 1px solid rgba(148, 163, 184, 0.2); }
    .badge-vpn { background: rgba(59, 130, 246, 0.2); color: #60a5fa; border: 1px solid rgba(59, 130, 246, 0.3); font-family: monospace; font-size: 13px; }
    .badge-platform { background: rgba(255, 255, 255, 0.08); color: #e2e8f0; font-size: 12px; text-transform: capitalize; }
    .btn { background: var(--primary); color: #fff; border: none; padding: 9px 18px; border-radius: 8px; font-size: 13px; font-weight: 600; cursor: pointer; transition: background 0.2s; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; }
    .btn:hover { background: var(--primary-hover); }
    .btn-outline { background: transparent; border: 1px solid var(--card-border); color: var(--text); }
    .btn-outline:hover { background: rgba(255, 255, 255, 0.05); border-color: #64748b; }
    .downloads-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin-top: 12px; }
    .download-item { background: rgba(255, 255, 255, 0.02); border: 1px solid var(--card-border); border-radius: 12px; padding: 16px; display: flex; align-items: center; justify-content: space-between; }
    .download-info h4 { font-size: 15px; margin-bottom: 2px; }
    .download-info p { font-size: 12px; color: var(--text-muted); }
    .empty-state { text-align: center; padding: 36px 16px; color: var(--text-muted); font-size: 14px; }
    footer { text-align: center; color: var(--text-muted); font-size: 12px; margin-top: 40px; padding-top: 20px; border-top: 1px solid var(--card-border); }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <div class="logo-area">
        <div class="logo-icon">⇄</div>
        <div>
          <h1>CrossDrop Administration</h1>
          <div class="subtitle">Zentraler Account-, Geräte- & Zero-Config VPN-Manager</div>
        </div>
      </div>
      <div style="display: flex; gap: 12px; align-items: center;">
        <span class="status-pill"><span class="status-dot"></span> Server Online (Port 2603)</span>
        <button class="btn btn-outline" onclick="loadStats()">🔄 Aktualisieren</button>
        <a href="/docs" target="_blank" class="btn btn-outline">📖 Swagger API</a>
      </div>
    </header>

    <!-- Stat Cards -->
    <div class="grid-stats">
      <div class="stat-card">
        <div>
          <div class="stat-title">Registrierte Accounts</div>
          <div class="stat-value" id="stat-users">0</div>
        </div>
        <div class="stat-meta">👥 Freie Selbstregistrierung aktiv</div>
      </div>

      <div class="stat-card">
        <div>
          <div class="stat-title">Registrierte Geräte</div>
          <div class="stat-value" id="stat-devices">0</div>
        </div>
        <div class="stat-meta">📱 Windows, Linux & Android</div>
      </div>

      <div class="stat-card">
        <div>
          <div class="stat-title">Aktive VPN-Tunnel</div>
          <div class="stat-value" id="stat-tunnels" style="color: #34d399;">0</div>
        </div>
        <div class="stat-meta">🔒 Zero-Config WebSocket-Tunnel</div>
      </div>

      <div class="stat-card">
        <div>
          <div class="stat-title">Server Uptime</div>
          <div class="stat-value" id="stat-uptime" style="font-size: 24px; padding-top: 4px;">0h 0m</div>
        </div>
        <div class="stat-meta">⏱️ Gestartet auf Port 2603</div>
      </div>
    </div>

    <!-- Connected Devices Table -->
    <div class="card">
      <div class="card-header">
        <div class="card-title">📱 Geräte & VPN-Verbindungsstatus</div>
      </div>
      <div style="overflow-x: auto;">
        <table>
          <thead>
            <tr>
              <th>Gerätename</th>
              <th>Plattform</th>
              <th>Besitzer (Konto)</th>
              <th>Lokale IPs</th>
              <th>VPN-IP (Virtuell)</th>
              <th>Status</th>
              <th>Zuletzt gesehen</th>
            </tr>
          </thead>
          <tbody id="devices-table-body">
            <tr><td colspan="7" class="empty-state">Lade Geräteübersicht...</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Registered Users Table -->
    <div class="card">
      <div class="card-header">
        <div class="card-title">👥 Registrierte Benutzer</div>
      </div>
      <div style="overflow-x: auto;">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Benutzername</th>
              <th>E-Mail</th>
              <th>Verknüpfte Geräte</th>
              <th>Registriert am</th>
            </tr>
          </thead>
          <tbody id="users-table-body">
            <tr><td colspan="5" class="empty-state">Lade Benutzerübersicht...</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- App Downloads Section -->
    <div class="card">
      <div class="card-header">
        <div class="card-title">🚀 Fertige Client-Downloads für Endnutzer</div>
      </div>
      <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 16px;">
        Alle Apps sind standardmäßig bereits auf diesen Server vorkonfiguriert:
      </p>
      <div class="downloads-grid">
        <div class="download-item">
          <div class="download-info">
            <h4>🖥️ Windows Setup (10 & 11)</h4>
            <p>Installation mit Desktop-Icon & Startmenü</p>
          </div>
          <a href="https://github.com/BuzziGHG/crossdrop/releases/download/v1.0.0/CrossDrop-Windows-Setup.exe" class="btn" target="_blank">Download Setup .exe</a>
        </div>
        <div class="download-item">
          <div class="download-info">
            <h4>🐧 Linux (Debian / Ubuntu)</h4>
            <p>Installierbares .deb Paket</p>
          </div>
          <a href="https://github.com/BuzziGHG/crossdrop/releases/download/v1.0.0/crossdrop_1.0.0_amd64.deb" class="btn" target="_blank">Download .deb</a>
        </div>
        <div class="download-item">
          <div class="download-info">
            <h4>📱 Android (Smartphone / Tablet)</h4>
            <p>Direkt installierbare APK</p>
          </div>
          <a href="https://github.com/BuzziGHG/crossdrop/releases/download/v1.0.0/crossdrop-release.apk" class="btn" target="_blank">Download .apk</a>
        </div>
      </div>
    <!-- In-App Auto-Update Server Section -->
    <div class="card">
      <div class="card-header">
        <div class="card-title">🔄 In-App Auto-Update Server</div>
        <span class="badge badge-online">🟢 Auto-Update Dienst Aktiv</span>
      </div>
      <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 20px;">
        Verwalten Sie App-Aktualisierungen direkt auf Ihrem Server. Verbundene Apps (Android, Windows, Linux) prüfen automatisch diese Schnittstelle und aktualisieren sich selbstständig, ohne dass Nutzer manuell APKs von GitHub herunterladen müssen.
      </p>

      <div style="background: rgba(255,255,255,0.03); border: 1px solid var(--card-border); border-radius: 12px; padding: 18px; margin-bottom: 20px;">
        <h4 style="margin-bottom: 12px; font-size: 15px;">Aktuelle Server-Update-Versionen</h4>
        <div style="display: flex; gap: 24px; flex-wrap: wrap;" id="update-versions-display">
          <div><span style="color: var(--text-muted); font-size: 12px;">ANDROID APK:</span> <strong id="up-ver-android">v1.0.0</strong></div>
          <div><span style="color: var(--text-muted); font-size: 12px;">WINDOWS:</span> <strong id="up-ver-windows">v1.0.0</strong></div>
          <div><span style="color: var(--text-muted); font-size: 12px;">LINUX .DEB:</span> <strong id="up-ver-linux">v1.0.0</strong></div>
        </div>
      </div>

      <!-- Upload Form for new APK / binary directly from browser -->
      <form id="upload-update-form" onsubmit="handleUpdateUpload(event)" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 14px; align-items: end;">
        <div>
          <label style="display: block; font-size: 12px; color: var(--text-muted); margin-bottom: 6px; font-weight: 600;">Plattform</label>
          <select id="up-platform" style="width: 100%; padding: 10px; border-radius: 8px; background: var(--bg); border: 1px solid var(--card-border); color: #fff;">
            <option value="android">📱 Android (.apk)</option>
            <option value="windows">🖥️ Windows (.zip)</option>
            <option value="linux">🐧 Linux (.deb)</option>
          </select>
        </div>
        <div>
          <label style="display: block; font-size: 12px; color: var(--text-muted); margin-bottom: 6px; font-weight: 600;">Neue Versionsnummer (z. B. 1.0.1)</label>
          <input type="text" id="up-version" placeholder="1.0.1" required style="width: 100%; padding: 10px; border-radius: 8px; background: var(--bg); border: 1px solid var(--card-border); color: #fff;">
        </div>
        <div>
          <label style="display: block; font-size: 12px; color: var(--text-muted); margin-bottom: 6px; font-weight: 600;">Update-Datei auswählen</label>
          <input type="file" id="up-file" required style="width: 100%; padding: 7px; border-radius: 8px; background: var(--bg); border: 1px solid var(--card-border); color: #fff;">
        </div>
        <div>
          <button type="submit" class="btn" style="width: 100%; padding: 10px; justify-content: center;" id="btn-upload-update">
            🚀 Update auf Server bereitstellen
          </button>
        </div>
      </form>
      <div id="upload-msg" style="margin-top: 12px; font-size: 13px; display: none;"></div>
    </div>

    <footer>
      CrossDrop Server v1.0.0 • Zentraler Datenaustausch- & VPN-Dienst • Läuft auf Port 2603
    </footer>
  </div>

  <script>
    async function loadStats() {
      try {
        const res = await fetch('/api/admin/stats');
        if (!res.ok) throw new Error("HTTP error " + res.status);
        const data = await res.json();

        document.getElementById('stat-users').innerText = data.total_users;
        document.getElementById('stat-devices').innerText = data.total_devices;
        document.getElementById('stat-tunnels').innerText = data.active_vpn_tunnels;
        document.getElementById('stat-uptime').innerText = data.uptime;

        // Devices
        const devBody = document.getElementById('devices-table-body');
        if (!data.devices || data.devices.length === 0) {
          devBody.innerHTML = '<tr><td colspan="7" class="empty-state">Noch keine Geräte registriert. Sobald sich eine App verbindet, erscheint sie hier.</td></tr>';
        } else {
          devBody.innerHTML = data.devices.map(d => {
            const statusBadge = d.is_tunnel_active 
              ? '<span class="badge badge-online">🟢 VPN Aktiv</span>' 
              : (d.is_online ? '<span class="badge badge-online">🟢 Online</span>' : '<span class="badge badge-offline">⚪ Offline</span>');
            
            const vpnBadge = d.vpn_ips && d.vpn_ips.length > 0 
              ? `<span class="badge badge-vpn">${d.vpn_ips.join(', ')}</span>`
              : '<span style="color: #64748b;">—</span>';

            const localIps = d.local_ips && d.local_ips.length > 0 ? d.local_ips.join(', ') : '—';

            return `
              <tr>
                <td><strong>${escapeHtml(d.name)}</strong></td>
                <td><span class="badge badge-platform">${escapeHtml(d.platform)}</span></td>
                <td>${escapeHtml(d.owner)}</td>
                <td style="font-family: monospace; font-size: 13px;">${escapeHtml(localIps)}</td>
                <td>${vpnBadge}</td>
                <td>${statusBadge}</td>
                <td style="color: var(--text-muted); font-size: 13px;">${escapeHtml(d.last_seen)}</td>
              </tr>
            `;
          }).join('');
        }

        // Users
        const userBody = document.getElementById('users-table-body');
        if (!data.users || data.users.length === 0) {
          userBody.innerHTML = '<tr><td colspan="5" class="empty-state">Noch keine Benutzer registriert. Neue Benutzer können sich in der App registrieren.</td></tr>';
        } else {
          userBody.innerHTML = data.users.map(u => `
            <tr>
              <td>#${u.id}</td>
              <td><strong>${escapeHtml(u.username)}</strong></td>
              <td>${escapeHtml(u.email)}</td>
              <td><span class="badge badge-platform">${u.devices_count} Gerät(e)</span></td>
              <td style="color: var(--text-muted); font-size: 13px;">${escapeHtml(u.created_at)}</td>
            </tr>
          `).join('');
        }
        loadUpdateStatus();
      } catch (err) {
        console.error("Fehler beim Laden der Admin-Statistiken:", err);
      }
    }

    async function loadUpdateStatus() {
      try {
        const res = await fetch('/api/updates/status');
        if (!res.ok) return;
        const data = await res.json();
        if (data.platforms) {
          if (data.platforms.android) {
            document.getElementById('up-ver-android').innerText = 'v' + data.platforms.android.version + (data.platforms.android.has_local_file ? ' (Lokal bereit)' : ' (GitHub Fallback)');
          }
          if (data.platforms.windows) {
            document.getElementById('up-ver-windows').innerText = 'v' + data.platforms.windows.version + (data.platforms.windows.has_local_file ? ' (Lokal bereit)' : ' (GitHub Fallback)');
          }
          if (data.platforms.linux) {
            document.getElementById('up-ver-linux').innerText = 'v' + data.platforms.linux.version + (data.platforms.linux.has_local_file ? ' (Lokal bereit)' : ' (GitHub Fallback)');
          }
        }
      } catch (e) {
        console.error("Error loading update status", e);
      }
    }

    async function handleUpdateUpload(e) {
      e.preventDefault();
      const platform = document.getElementById('up-platform').value;
      const version = document.getElementById('up-version').value.trim();
      const fileInput = document.getElementById('up-file');
      const msg = document.getElementById('upload-msg');
      const btn = document.getElementById('btn-upload-update');

      if (!fileInput.files || fileInput.files.length === 0) {
        alert("Bitte eine Datei auswählen!");
        return;
      }

      const formData = new FormData();
      formData.append('platform', platform);
      formData.append('version', version);
      formData.append('file', fileInput.files[0]);

      btn.disabled = true;
      btn.innerText = "⏳ Lade Datei hoch...";
      msg.style.display = 'block';
      msg.style.color = '#38bdf8';
      msg.innerText = "Upload läuft... Bitte warten.";

      try {
        const res = await fetch('/api/updates/upload', {
          method: 'POST',
          body: formData
        });
        const result = await res.json();
        if (res.ok) {
          msg.style.color = '#34d399';
          msg.innerText = "✅ " + result.message + " Apps erhalten dieses Update nun automatisch!";
          fileInput.value = '';
          loadUpdateStatus();
        } else {
          msg.style.color = '#ef4444';
          msg.innerText = "❌ Fehler: " + (result.detail || "Upload fehlgeschlagen");
        }
      } catch (err) {
        msg.style.color = '#ef4444';
        msg.innerText = "❌ Netzwerkfehler beim Upload: " + err.message;
      } finally {
        btn.disabled = false;
        btn.innerText = "🚀 Update auf Server bereitstellen";
      }
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    loadStats();
    setInterval(loadStats, 8000);
  </script>
</body>
</html>
"""
    return HTMLResponse(content=html_content)

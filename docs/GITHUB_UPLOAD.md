# Schritt-für-Schritt-Anleitung: Auf GitHub hochladen & fertige `.exe`, `.deb`, `.apk` herunterladen

Mit dieser Anleitung laden Sie CrossDrop in Ihr persönliches GitHub-Konto hoch. **GitHub baut anschließend vollautomatisch alle drei Apps in der Cloud**, sodass Sie keine riesigen SDKs auf Ihrem PC installieren müssen.

---

## Schritt 1: Neues Repository auf GitHub erstellen

1. Öffnen Sie [github.com](https://github.com) und melden Sie sich an.
2. Klicken Sie oben rechts auf das **`+`**-Symbol und wählen Sie **„New repository“**.
3. Geben Sie dem Repository einen Namen (z. B. `crossdrop`).
4. Wählen Sie **Private** (oder Public, wie Sie möchten).
5. **WICHTIG:** Lassen Sie alle Häkchen bei *„Add a README file“*, *„Add .gitignore“* etc. **DEAKTIVIERT** (leer lassen).
6. Klicken Sie auf **„Create repository“**.
7. Kopieren Sie die angezeigte HTTPS-URL (z. B. `https://github.com/IhrName/crossdrop.git`).

---

## Schritt 2: Projekt hochladen

### Option A: Mit dem mitgelieferten Skript (Einfachste Methode)
1. Öffnen Sie den Ordner:
   `C:\Users\S.Dialler\.gemini\antigravity\scratch\crossdrop`
2. Machen Sie einen Doppelklick auf **`upload_to_github.bat`**.
3. Fügen Sie die kopierte GitHub-Repository-URL ein und drücken Sie **Enter**.
4. Falls Git noch nicht auf Ihrem PC installiert ist, installieren Sie kurz [Git für Windows](https://git-scm.com/download/win) (Standardeinstellungen genügen).

### Option B: Über GitHub Desktop
1. Laden Sie [GitHub Desktop](https://desktop.github.com) herunter (falls noch nicht vorhanden).
2. Klicken Sie auf **File > Add local repository...**
3. Wählen Sie den Ordner `C:\Users\S.Dialler\.gemini\antigravity\scratch\crossdrop`.
4. Klicken Sie auf **Publish repository**, um es auf Ihr GitHub-Profil hochzuladen.

---

## Schritt 3: Fertige `.exe`, `.deb` und `.apk` herunterladen

Sobald der Code auf GitHub hochgeladen ist, startet die GitHub Actions Pipeline automatisch:

1. Öffnen Sie Ihr Repository auf GitHub im Browser.
2. Klicken Sie oben auf den Reiter **„Actions“**:
   - Sie sehen einen laufenden Build mit dem Namen **„Build & Release CrossDrop“**.
   - GitHub startet 3 virtuelle Maschinen (Windows, Ubuntu, Android-Builder) gleichzeitig.
3. Nach ca. 3 bis 5 Minuten wird der Build grün (Erfolgreich).
4. Klicken Sie im Repository rechts auf **„Releases“** (oder rufen Sie `https://github.com/IhrName/crossdrop/releases` auf).
5. **Dort finden Sie alle 3 fertigen Dateien zum direkten Download:**
   - 🖥️ **`CrossDrop-Windows-x64.zip`** (Herunterladen, entpacken und `crossdrop.exe` starten)
   - 🐧 **`crossdrop_1.0.0_amd64.deb`** (Mit `sudo dpkg -i crossdrop_1.0.0_amd64.deb` auf Debian/Ubuntu installieren)
   - 📱 **`crossdrop-release.apk`** (Auf das Android-Gerät übertragen und installieren)

---

## Schritt 4: Server auf Ihrem Linux-Server starten

1. Kopieren Sie den Ordner `server/` auf Ihren Linux-Server:
   ```bash
   scp -r server benutzer@ihr-server-ip:/opt/crossdrop-server
   ```
2. Auf dem Server starten:
   ```bash
   cd /opt/crossdrop-server
   docker compose up -d --build
   ```
3. Öffnen Sie die App auf Windows, Linux oder Android:
   - Tragen Sie Ihre Server-URL ein (z. B. `http://ihr-server-ip:8000` oder Ihre Domain).
   - Jeder Benutzer kann sich direkt mit eigener E-Mail und Passwort ein Konto anlegen.
   - Die App verbindet sich **vollautomatisch über den integrierten VPN-Tunnel** mit dem Server – **0 manuelle Konfiguration nötig!**

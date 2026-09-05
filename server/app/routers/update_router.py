import os
import json
import shutil
import logging
import urllib.request
from datetime import datetime
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Query, Body
from fastapi.responses import FileResponse, RedirectResponse
import requests

router = APIRouter(prefix="/api/updates", tags=["In-App Auto Update Server"])
logger = logging.getLogger("crossdrop.updates")

DATA_DIR = os.getenv("DATA_DIR", "/data")
UPDATES_DIR = os.path.join(DATA_DIR, "updates")
ARCHIVE_DIR = os.path.join(UPDATES_DIR, "archive")
METADATA_FILE = os.path.join(UPDATES_DIR, "version.json")

os.makedirs(UPDATES_DIR, exist_ok=True)
os.makedirs(ARCHIVE_DIR, exist_ok=True)
for p in ["android", "windows", "linux"]:
    os.makedirs(os.path.join(UPDATES_DIR, p), exist_ok=True)

DEFAULT_METADATA = {
    "latest_version": "1.0.0",
    "release_notes": "Offizielle Version mit LAN & automatischem VPN-Tunnel.",
    "updated_at": datetime.utcnow().isoformat(),
    "platforms": {
        "android": {
            "version": "1.0.0",
            "file_name": "crossdrop-release.apk",
            "github_fallback": "https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop-release.apk"
        },
        "windows": {
            "version": "1.0.0",
            "file_name": "CrossDrop-Windows-Setup.exe",
            "github_fallback": "https://github.com/BuzziGHG/crossdrop/releases/latest/download/CrossDrop-Windows-Setup.exe"
        },
        "linux": {
            "version": "1.0.0",
            "file_name": "crossdrop_1.0.0_amd64.deb",
            "github_fallback": "https://github.com/BuzziGHG/crossdrop/releases/latest/download/crossdrop_1.0.0_amd64.deb"
        }
    },
    "history": [
        {
            "version": "1.0.0",
            "created_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
            "release_notes": "Initiale Release-Version mit VPN & LAN Transfer",
            "platforms": ["android", "windows", "linux"]
        }
    ]
}

def load_metadata() -> dict:
    if os.path.exists(METADATA_FILE):
        try:
            with open(METADATA_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                if "history" not in data:
                    data["history"] = DEFAULT_METADATA["history"].copy()
                return data
        except Exception as e:
            logger.error(f"Error reading {METADATA_FILE}: {e}")
    return DEFAULT_METADATA.copy()

def save_metadata(meta: dict):
    try:
        with open(METADATA_FILE, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except Exception as e:
        logger.error(f"Error saving {METADATA_FILE}: {e}")

def parse_version(v_str: str):
    """Parses semver-like version string into integer tuple for comparison."""
    cleaned = v_str.lower().lstrip("v").split("+")[0].split("-")[0]
    parts = []
    for p in cleaned.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)

@router.get("/check")
def check_for_update(
    platform: str = Query(..., description="android, windows, linux"),
    current_version: str = Query("1.0.0", description="Current app version, e.g. 1.0.0")
):
    platform = platform.lower().strip()
    meta = load_metadata()
    plat_info = meta.get("platforms", {}).get(platform)
    
    if not plat_info:
        return {
            "has_update": False,
            "current_version": current_version,
            "latest_version": current_version,
            "message": f"Keine Updates für Plattform {platform} registriert."
        }

    latest_ver = plat_info.get("version", meta.get("latest_version", "1.0.0"))
    curr_tuple = parse_version(current_version)
    latest_tuple = parse_version(latest_ver)

    has_update = latest_tuple > curr_tuple

    local_file = os.path.join(UPDATES_DIR, platform, plat_info.get("file_name", ""))
    has_local = os.path.exists(local_file) and os.path.getsize(local_file) > 0
    file_size = os.path.getsize(local_file) if has_local else 0

    return {
        "has_update": has_update,
        "current_version": current_version,
        "latest_version": latest_ver,
        "release_notes": meta.get("release_notes", "Neue Version verfügbar."),
        "download_url": f"/api/updates/download/{platform}",
        "file_name": plat_info.get("file_name", ""),
        "file_size": file_size,
        "is_hosted_locally": has_local
    }

@router.get("/download/{platform}")
def download_update(platform: str):
    platform = platform.lower().strip()
    meta = load_metadata()
    plat_info = meta.get("platforms", {}).get(platform)
    
    if not plat_info:
        raise HTTPException(status_code=404, detail=f"Plattform {platform} nicht gefunden.")

    file_name = plat_info.get("file_name", "update.bin")
    local_path = os.path.join(UPDATES_DIR, platform, file_name)

    if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
        media_types = {
            "android": "application/vnd.android.package-archive",
            "windows": "application/x-msdownload",
            "linux": "application/vnd.debian.binary-package"
        }
        return FileResponse(
            path=local_path,
            filename=file_name,
            media_type=media_types.get(platform, "application/octet-stream")
        )

    # Fallback to GitHub releases if file not yet uploaded directly to server
    fallback_url = plat_info.get("github_fallback")
    if fallback_url:
        return RedirectResponse(url=fallback_url)

    raise HTTPException(status_code=404, detail="Update-Datei auf dem Server nicht gefunden.")

@router.post("/upload")
async def upload_update_file(
    platform: str = Form(...),
    version: str = Form(...),
    release_notes: Optional[str] = Form("Neues Update bereitgestellt."),
    file: UploadFile = File(...)
):
    platform = platform.lower().strip()
    if platform not in ["android", "windows", "linux"]:
        raise HTTPException(status_code=400, detail="Ungültige Plattform. Erlaubt: android, windows, linux")

    # 1. Save to active directory
    target_dir = os.path.join(UPDATES_DIR, platform)
    os.makedirs(target_dir, exist_ok=True)
    target_path = os.path.join(target_dir, file.filename)

    content = await file.read()
    with open(target_path, "wb") as f:
        f.write(content)

    # 2. Archive copy for rollback support
    archive_version_dir = os.path.join(ARCHIVE_DIR, version, platform)
    os.makedirs(archive_version_dir, exist_ok=True)
    with open(os.path.join(archive_version_dir, file.filename), "wb") as f:
        f.write(content)

    # 3. Update metadata
    meta = load_metadata()
    meta["latest_version"] = version
    meta["release_notes"] = release_notes
    meta["updated_at"] = datetime.utcnow().isoformat()
    if "platforms" not in meta:
        meta["platforms"] = {}
    meta["platforms"][platform] = {
        "version": version,
        "file_name": file.filename,
        "file_size": len(content),
        "uploaded_at": datetime.utcnow().isoformat()
    }

    # Add to history
    history = meta.get("history", [])
    existing_entry = next((h for h in history if h.get("version") == version), None)
    if existing_entry:
        if platform not in existing_entry.get("platforms", []):
            existing_entry.setdefault("platforms", []).append(platform)
        existing_entry["updated_at"] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    else:
        history.insert(0, {
            "version": version,
            "created_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
            "release_notes": release_notes or "Manuelles Update",
            "platforms": [platform]
        })
    meta["history"] = history
    save_metadata(meta)

    return {
        "status": "success",
        "message": f"Update für {platform} (v{version}) erfolgreich bereitgestellt & archiviert!",
        "platform": platform,
        "version": version,
        "file_name": file.filename,
        "file_size": len(content),
        "download_url": f"/api/updates/download/{platform}"
    }

@router.post("/sync-github")
def sync_latest_from_github(repo: str = "BuzziGHG/crossdrop"):
    """
    Fetches the latest release from GitHub, downloads all binaries into local storage,
    archives them and activates the new version automatically.
    """
    api_url = f"https://api.github.com/repos/{repo}/releases/latest"
    try:
        resp = requests.get(api_url, headers={"User-Agent": "CrossDrop-Server"}, timeout=10)
        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"GitHub API meldete Status {resp.status_code}")

        release_data = resp.json()
        tag = release_data.get("tag_name", "v1.0.0").lstrip("v")
        notes = release_data.get("body", "GitHub Release")
        assets = release_data.get("assets", [])

        downloaded_platforms = []
        archive_version_dir = os.path.join(ARCHIVE_DIR, tag)
        os.makedirs(archive_version_dir, exist_ok=True)

        for asset in assets:
            name = asset.get("name", "")
            download_url = asset.get("browser_download_url")
            if not name or not download_url:
                continue

            platform = None
            target_name = None

            if name.endswith(".apk"):
                platform = "android"
                target_name = "crossdrop-release.apk"
            elif name.endswith(".exe") and "setup" in name.lower():
                platform = "windows"
                target_name = "CrossDrop-Windows-Setup.exe"
            elif name.endswith(".deb"):
                platform = "linux"
                target_name = name

            if not platform:
                continue

            # Download stream
            active_path = os.path.join(UPDATES_DIR, platform, target_name)
            with requests.get(download_url, headers={"User-Agent": "CrossDrop-Server"}, stream=True, timeout=60) as r:
                r.raise_for_status()
                with open(active_path, "wb") as f:
                    for chunk in r.iter_content(chunk_size=65536):
                        if chunk:
                            f.write(chunk)

            # Archive copy for rollback
            arch_dir = os.path.join(archive_version_dir, platform)
            os.makedirs(arch_dir, exist_ok=True)
            shutil.copy2(active_path, os.path.join(arch_dir, target_name))

            downloaded_platforms.append(platform)

        meta = load_metadata()
        meta["latest_version"] = tag
        meta["release_notes"] = notes
        meta["updated_at"] = datetime.utcnow().isoformat()

        if "platforms" not in meta:
            meta["platforms"] = {}

        for p in set(downloaded_platforms):
            if p not in meta["platforms"]:
                meta["platforms"][p] = {}
            meta["platforms"][p]["version"] = tag
            
            # Find the target filename used
            target_file = "crossdrop-release.apk" if p == "android" else ("CrossDrop-Windows-Setup.exe" if p == "windows" else next((a.get("name") for a in assets if a.get("name", "").endswith(".deb")), "crossdrop.deb"))
            meta["platforms"][p]["file_name"] = target_file
            
            local_path = os.path.join(UPDATES_DIR, p, target_file)
            if os.path.exists(local_path):
                meta["platforms"][p]["file_size"] = os.path.getsize(local_path)
            meta["platforms"][p]["uploaded_at"] = datetime.utcnow().isoformat()

        # Update history
        history = meta.get("history", [])
        existing = next((h for h in history if h.get("version") == tag), None)
        if not existing:
            history.insert(0, {
                "version": tag,
                "created_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
                "release_notes": f"GitHub Release Synchronisation ({tag})",
                "platforms": list(set(downloaded_platforms))
            })
        else:
            existing["platforms"] = list(set(downloaded_platforms))
            existing["release_notes"] = f"GitHub Release Synchronisation ({tag})"
        meta["history"] = history
        save_metadata(meta)

        return {
            "status": "success",
            "message": f"Release v{tag} erfolgreich von GitHub synchronisiert und aktiviert!",
            "version": tag,
            "synced_platforms": list(set(downloaded_platforms))
        }

    except Exception as e:
        logger.error(f"GitHub sync error: {e}")
        raise HTTPException(status_code=500, detail=f"Fehler bei GitHub-Synchronisation: {str(e)}")

@router.post("/rollback")
def rollback_to_version(data: dict = Body(...)):
    """
    Rolls back the active update version to a previous version stored in archive.
    """
    target_version = data.get("version", "").strip().lstrip("v")
    if not target_version:
        raise HTTPException(status_code=400, detail="Keine Zielversion angegeben.")

    meta = load_metadata()
    history = meta.get("history", [])
    entry = next((h for h in history if h.get("version") == target_version), None)

    if not entry:
        raise HTTPException(status_code=404, detail=f"Version {target_version} wurde in der Historie nicht gefunden.")

    archive_version_dir = os.path.join(ARCHIVE_DIR, target_version)
    if os.path.exists(archive_version_dir):
        # Restore archived files
        for p in ["android", "windows", "linux"]:
            p_arch = os.path.join(archive_version_dir, p)
            if os.path.exists(p_arch):
                for fname in os.listdir(p_arch):
                    src = os.path.join(p_arch, fname)
                    dst = os.path.join(UPDATES_DIR, p, fname)
                    if os.path.isfile(src):
                        shutil.copy2(src, dst)
                        if "platforms" in meta and p in meta["platforms"]:
                            meta["platforms"][p]["file_name"] = fname
                            meta["platforms"][p]["file_size"] = os.path.getsize(dst)

    meta["latest_version"] = target_version
    meta["release_notes"] = f"Rollback auf Version {target_version}"
    meta["updated_at"] = datetime.utcnow().isoformat()

    for p, p_info in meta.get("platforms", {}).items():
        p_info["version"] = target_version

    save_metadata(meta)

    return {
        "status": "success",
        "message": f"Erfolgreich auf Version v{target_version} zurückgerollt! Verbundene Apps werden auf diese Version ausgerichtet.",
        "active_version": target_version
    }

@router.get("/status")
def get_update_server_status():
    meta = load_metadata()
    status_platforms = {}
    for p in ["android", "windows", "linux"]:
        plat_info = meta.get("platforms", {}).get(p, {})
        file_name = plat_info.get("file_name", "")
        local_path = os.path.join(UPDATES_DIR, p, file_name) if file_name else ""
        has_file = os.path.exists(local_path) and os.path.getsize(local_path) > 0
        status_platforms[p] = {
            "version": plat_info.get("version", meta.get("latest_version", "1.0.0")),
            "file_name": file_name,
            "has_local_file": has_file,
            "file_size": os.path.getsize(local_path) if has_file else 0
        }
    return {
        "latest_version": meta.get("latest_version", "1.0.0"),
        "release_notes": meta.get("release_notes", ""),
        "platforms": status_platforms,
        "history": meta.get("history", [])
    }

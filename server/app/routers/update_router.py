import os
import json
import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Query, Response
from fastapi.responses import FileResponse, RedirectResponse

router = APIRouter(prefix="/api/updates", tags=["In-App Auto Update Server"])
logger = logging.getLogger("crossdrop.updates")

DATA_DIR = os.getenv("DATA_DIR", "/data")
UPDATES_DIR = os.path.join(DATA_DIR, "updates")
METADATA_FILE = os.path.join(UPDATES_DIR, "version.json")

os.makedirs(UPDATES_DIR, exist_ok=True)
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
    }
}

def load_metadata() -> dict:
    if os.path.exists(METADATA_FILE):
        try:
            with open(METADATA_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
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
            "windows": "application/zip",
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

    target_dir = os.path.join(UPDATES_DIR, platform)
    os.makedirs(target_dir, exist_ok=True)
    target_path = os.path.join(target_dir, file.filename)

    with open(target_path, "wb") as f:
        content = await file.read()
        f.write(content)

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
    save_metadata(meta)

    return {
        "status": "success",
        "message": f"Update für {platform} erfolgreich auf dem Server gespeichert!",
        "platform": platform,
        "version": version,
        "file_name": file.filename,
        "file_size": len(content),
        "download_url": f"/api/updates/download/{platform}"
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
        "platforms": status_platforms
    }

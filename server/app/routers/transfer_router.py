import os
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from app.database import get_db, User, Device
from app.schemas import TransferSignal
from app.auth import get_current_user

router = APIRouter(prefix="/api/transfer", tags=["Transfer Signaling & Relay"])
logger = logging.getLogger("crossdrop.transfer")

DATA_DIR = os.getenv("DATA_DIR", "/data")
RELAY_DIR = os.path.join(DATA_DIR, "relay")
os.makedirs(RELAY_DIR, exist_ok=True)

# In-memory signal buffer for pending transfer requests: target_device_id -> list of signals
pending_signals: Dict[str, List[dict]] = {}
relay_meta: Dict[str, dict] = {}

@router.post("/signal")
def send_signal(
    signal: TransferSignal,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    target = db.query(Device).filter(
        Device.id == signal.target_device_id,
        Device.owner_id == current_user.id
    ).first()

    if not target:
        raise HTTPException(status_code=404, detail="Zielgerät nicht gefunden oder gehört nicht zu diesem Account.")

    if signal.target_device_id not in pending_signals:
        pending_signals[signal.target_device_id] = []

    payload = signal.dict()
    payload["timestamp"] = str(datetime.utcnow())
    pending_signals[signal.target_device_id].append(payload)

    return {"status": "signal_queued", "target_device": target.name}

@router.get("/signals/{device_id}")
def get_pending_signals(
    device_id: str,
    current_user: User = Depends(get_current_user)
):
    signals = pending_signals.pop(device_id, [])
    return {"signals": signals}

# --- Server Relay Endpoints for Zero-Config Remote Transfers ---

@router.post("/relay/upload/{task_id}")
async def relay_upload(
    task_id: str,
    request: Request,
    filename: str = Query("transfer.bin"),
    size: int = Query(0),
    sender_name: str = Query("Gerät")
):
    """Stores a file chunk/stream on the server relay for the receiver to pick up."""
    task_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    
    with open(task_file, "wb") as f:
        async for chunk in request.stream():
            f.write(chunk)

    actual_size = os.path.getsize(task_file)
    relay_meta[task_id] = {
        "filename": filename,
        "size": actual_size,
        "sender_name": sender_name,
        "created_at": datetime.utcnow().isoformat()
    }

    return {
        "status": "ready",
        "task_id": task_id,
        "filename": filename,
        "size": actual_size,
        "download_url": f"/api/transfer/relay/download/{task_id}"
    }

@router.get("/relay/info/{task_id}")
def relay_info(task_id: str):
    info = relay_meta.get(task_id)
    task_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    if not os.path.exists(task_file):
        raise HTTPException(status_code=404, detail="Übertragungsdatei auf dem Server nicht gefunden.")
    return info or {"filename": "download.bin", "size": os.path.getsize(task_file)}

@router.get("/relay/download/{task_id}")
def relay_download(task_id: str):
    task_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    if not os.path.exists(task_file):
        raise HTTPException(status_code=404, detail="Übertragungsdatei existiert nicht oder wurde bereits abgeholt.")
    
    info = relay_meta.get(task_id, {})
    filename = info.get("filename", "transfer.bin")
    
    return FileResponse(
        path=task_file,
        filename=filename,
        media_type="application/octet-stream"
    )

@router.delete("/relay/{task_id}")
def relay_cleanup(task_id: str):
    task_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    if os.path.exists(task_file):
        try:
            os.remove(task_file)
        except Exception:
            pass
    relay_meta.pop(task_id, None)
    return {"status": "deleted"}


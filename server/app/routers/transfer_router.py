import os
import json
import logging
import asyncio
from datetime import datetime
from typing import Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import FileResponse, StreamingResponse
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
        Device.user_id == current_user.id
    ).first()

    if not target:
        raise HTTPException(status_code=404, detail="Zielgerät nicht gefunden oder gehört nicht zu diesem Account.")

    if signal.target_device_id not in pending_signals:
        pending_signals[signal.target_device_id] = []

    payload = signal.dict()
    payload["timestamp"] = str(datetime.utcnow())
    pending_signals[signal.target_device_id].append(payload)

    return {"status": "signal_queued", "target_device": target.name}

@router.get("/lookup-recipient")
def lookup_recipient(
    email: str = Query(..., min_length=3),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    clean_email = email.strip().lower()
    if clean_email == current_user.email.strip().lower():
        raise HTTPException(
            status_code=400,
            detail="Sie können nicht an Ihre eigene E-Mail-Adresse senden. Wählen Sie Ihr Gerät bitte direkt aus der Geräteliste."
        )

    recipient = db.query(User).filter(User.email.ilike(clean_email)).first()
    if not recipient:
        raise HTTPException(status_code=404, detail="Kein Benutzer mit dieser E-Mail-Adresse registriert.")

    from app.routers.vpn_router import active_tunnels
    devices = db.query(Device).filter(Device.user_id == recipient.id).all()

    online_device = None
    for d in devices:
        if d.id in active_tunnels:
            online_device = d
            break

    if not online_device and devices:
        now = datetime.utcnow()
        for d in devices:
            if d.is_online and (now - d.last_seen).total_seconds() < 60:
                online_device = d
                break

    target_dev = online_device or (devices[0] if devices else None)

    return {
        "found": True,
        "recipient_id": recipient.id,
        "email": recipient.email,
        "username": recipient.username,
        "has_online_device": online_device is not None,
        "target_device_id": target_dev.id if target_dev else None,
        "target_device_name": target_dev.name if target_dev else None,
    }

@router.get("/signals/{device_id}")
def get_pending_signals(
    device_id: str,
    current_user: User = Depends(get_current_user)
):
    signals = pending_signals.pop(device_id, [])
    return {"signals": signals}

# --- Zero-Disk In-Memory Streaming Relay Pipe ---

class RelayPipe:
    def __init__(self, task_id: str, filename: str = "transfer.bin", total_size: int = 0, sender_name: str = "Gerät"):
        self.task_id = task_id
        self.filename = filename
        self.total_size = total_size
        self.sender_name = sender_name
        self.created_at = datetime.utcnow()
        # Bounded queue holds max 16 chunks (~1 MB total in RAM). Zero bytes written to disk!
        self.queue: asyncio.Queue = asyncio.Queue(maxsize=16)
        self.sender_connected = asyncio.Event()
        self.receiver_connected = asyncio.Event()
        self.receiver_finished = asyncio.Event()
        self.aborted = False
        self.error: Optional[str] = None

active_pipes: Dict[str, RelayPipe] = {}

@router.post("/relay/pipe/{task_id}/upload")
async def relay_pipe_upload(
    task_id: str,
    request: Request,
    filename: str = Query("transfer.bin"),
    size: int = Query(0),
    sender_name: str = Query("Gerät")
):
    """
    Zero-disk in-memory streaming upload.
    Waits for receiver to connect, then streams chunks directly into memory queue.
    """
    pipe = active_pipes.get(task_id)
    if not pipe:
        pipe = RelayPipe(task_id=task_id, filename=filename, total_size=size, sender_name=sender_name)
        active_pipes[task_id] = pipe
    else:
        pipe.filename = filename
        pipe.total_size = size
        pipe.sender_name = sender_name

    pipe.sender_connected.set()
    logger.info(f"RelayPipe [{task_id}]: Sender '{sender_name}' verbunden. Warte auf Empfänger...")

    # Wait for receiver to connect (up to 120s)
    try:
        await asyncio.wait_for(pipe.receiver_connected.wait(), timeout=120.0)
    except asyncio.TimeoutError:
        pipe.aborted = True
        active_pipes.pop(task_id, None)
        logger.warning(f"RelayPipe [{task_id}]: Timeout beim Warten auf Empfänger.")
        raise HTTPException(status_code=408, detail="Zeitüberschreitung: Empfänger hat sich nicht rechtzeitig verbunden.")

    logger.info(f"RelayPipe [{task_id}]: Empfänger verbunden! Beginne synchrones Streaming...")

    try:
        async for chunk in request.stream():
            if pipe.aborted:
                raise HTTPException(status_code=499, detail=pipe.error or "Empfänger hat Verbindung getrennt.")
            
            # Put chunk in memory queue (blocks if queue is full = TCP backpressure)
            while not pipe.aborted:
                try:
                    await asyncio.wait_for(pipe.queue.put(chunk), timeout=1.0)
                    break
                except asyncio.TimeoutError:
                    continue

            if pipe.aborted:
                raise HTTPException(status_code=499, detail=pipe.error or "Empfänger hat Verbindung getrennt.")

        # Stream complete: send EOF sentinel
        await pipe.queue.put(None)
        logger.info(f"RelayPipe [{task_id}]: Alle Chunks vom Sender gestreamt. Warte auf Empfangsbestätigung...")

        # Wait for receiver to finish reading the queue (up to 30s)
        try:
            await asyncio.wait_for(pipe.receiver_finished.wait(), timeout=30.0)
        except asyncio.TimeoutError:
            pass

        return {"status": "completed", "task_id": task_id}
    except Exception as e:
        pipe.aborted = True
        pipe.error = str(e)
        try:
            pipe.queue.put_nowait(None)
        except Exception:
            pass
        logger.error(f"RelayPipe [{task_id}] Upload-Fehler: {e}")
        raise HTTPException(status_code=500, detail=f"Übertragungsfehler beim Upload: {e}")
    finally:
        active_pipes.pop(task_id, None)


@router.get("/relay/pipe/{task_id}/download")
async def relay_pipe_download(task_id: str):
    """
    Zero-disk in-memory streaming download.
    Streams chunks directly from memory queue without saving anything to server disk.
    """
    pipe = active_pipes.get(task_id)
    if not pipe:
        pipe = RelayPipe(task_id=task_id)
        active_pipes[task_id] = pipe

    pipe.receiver_connected.set()
    logger.info(f"RelayPipe [{task_id}]: Empfänger verbunden. Warte auf Sender...")

    # Wait for sender to connect (up to 120s)
    try:
        await asyncio.wait_for(pipe.sender_connected.wait(), timeout=120.0)
    except asyncio.TimeoutError:
        pipe.aborted = True
        active_pipes.pop(task_id, None)
        logger.warning(f"RelayPipe [{task_id}]: Timeout beim Warten auf Sender.")
        raise HTTPException(status_code=408, detail="Zeitüberschreitung: Sender hat sich nicht verbunden.")

    logger.info(f"RelayPipe [{task_id}]: Sender und Empfänger aktiv. Starte Live-Streaming-Download ({pipe.filename}, {pipe.total_size} Bytes)...")

    async def stream_generator():
        try:
            while True:
                if pipe.aborted:
                    break
                chunk = await pipe.queue.get()
                if chunk is None:
                    # EOF sentinel
                    pipe.receiver_finished.set()
                    break
                yield chunk
        except Exception as err:
            pipe.aborted = True
            pipe.error = str(err)
            logger.error(f"RelayPipe [{task_id}] Download Stream-Fehler: {err}")
            raise
        finally:
            pipe.receiver_finished.set()
            pipe.aborted = True
            active_pipes.pop(task_id, None)

    headers = {
        "Content-Disposition": f'attachment; filename="{pipe.filename}"',
    }
    if pipe.total_size > 0:
        headers["Content-Length"] = str(pipe.total_size)

    return StreamingResponse(
        stream_generator(),
        media_type="application/octet-stream",
        headers=headers
    )


@router.get("/relay/pipe/{task_id}/info")
def relay_pipe_info(task_id: str):
    pipe = active_pipes.get(task_id)
    if not pipe:
        raise HTTPException(status_code=404, detail="Relay-Pipe nicht gefunden.")
    return {
        "task_id": pipe.task_id,
        "filename": pipe.filename,
        "size": pipe.total_size,
        "sender_name": pipe.sender_name,
        "sender_connected": pipe.sender_connected.is_set(),
        "receiver_connected": pipe.receiver_connected.is_set(),
    }


# --- Legacy Fallback Relay Endpoints (for backwards compatibility) ---

@router.post("/relay/upload/{task_id}")
async def relay_upload(
    task_id: str,
    request: Request,
    filename: str = Query("transfer.bin"),
    size: int = Query(0),
    sender_name: str = Query("Gerät")
):
    """Legacy endpoint: Stores a file chunk/stream on disk."""
    temp_file = os.path.join(RELAY_DIR, f"{task_id}.uploading")
    final_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    
    try:
        with open(temp_file, "wb") as f:
            async for chunk in request.stream():
                f.write(chunk)

        if os.path.exists(temp_file):
            os.replace(temp_file, final_file)
            actual_size = os.path.getsize(final_file)
            relay_meta[task_id] = {
                "status": "ready",
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
        else:
            raise HTTPException(status_code=500, detail="Upload konnte nicht fertiggestellt werden.")
    except Exception as e:
        if os.path.exists(temp_file):
            try:
                os.remove(temp_file)
            except Exception:
                pass
        raise HTTPException(status_code=500, detail=f"Fehler beim Server-Relay-Upload: {e}")

@router.get("/relay/info/{task_id}")
def relay_info(task_id: str):
    info = relay_meta.get(task_id)
    final_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    if not info or info.get("status") != "ready" or not os.path.exists(final_file):
        raise HTTPException(status_code=404, detail="Übertragungsdatei wird noch vom Sender hochgeladen...")
    return info

@router.get("/relay/download/{task_id}")
def relay_download(task_id: str):
    info = relay_meta.get(task_id)
    final_file = os.path.join(RELAY_DIR, f"{task_id}.bin")
    if not info or info.get("status") != "ready" or not os.path.exists(final_file):
        raise HTTPException(status_code=404, detail="Übertragungsdatei ist noch nicht bereit oder existiert nicht.")
    
    filename = info.get("filename", "transfer.bin")
    
    return FileResponse(
        path=final_file,
        filename=filename,
        media_type="application/octet-stream"
    )

@router.delete("/relay/{task_id}")
def relay_cleanup(task_id: str):
    for ext in [".bin", ".uploading"]:
        fpath = os.path.join(RELAY_DIR, f"{task_id}{ext}")
        if os.path.exists(fpath):
            try:
                os.remove(fpath)
            except Exception:
                pass
    relay_meta.pop(task_id, None)
    active_pipes.pop(task_id, None)
    return {"status": "deleted"}



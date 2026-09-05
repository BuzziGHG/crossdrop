from datetime import datetime
from typing import Dict, List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db, User, Device
from app.schemas import TransferSignal
from app.auth import get_current_user

router = APIRouter(prefix="/api/transfer", tags=["Transfer Signaling"])

# In-memory signal buffer for pending transfer requests: target_device_id -> list of signals
pending_signals: Dict[str, List[dict]] = {}

@router.post("/signal")
def send_signal(
    signal: TransferSignal,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify target device belongs to same user
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

@router.get("/signals/{device_id}")
def get_pending_signals(
    device_id: str,
    current_user: User = Depends(get_current_user)
):
    signals = pending_signals.pop(device_id, [])
    return {"signals": signals}

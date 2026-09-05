import json
from datetime import datetime, timedelta
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db, User, Device
from app.schemas import DeviceRegister, DeviceHeartbeat, DeviceResponse
from app.auth import get_current_user

router = APIRouter(prefix="/api/devices", tags=["Devices"])

ONLINE_TIMEOUT_SECONDS = 45

@router.get("", response_model=List[DeviceResponse])
def get_user_devices(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    devices = db.query(Device).filter(Device.user_id == current_user.id).all()
    now = datetime.utcnow()
    result = []
    
    for dev in devices:
        # Determine if online based on last_seen
        is_active = (now - dev.last_seen) < timedelta(seconds=ONLINE_TIMEOUT_SECONDS)
        
        try:
            local_list = json.loads(dev.local_ips) if dev.local_ips else []
        except Exception:
            local_list = []
            
        try:
            vpn_list = json.loads(dev.vpn_ips) if dev.vpn_ips else []
        except Exception:
            vpn_list = []

        result.append(DeviceResponse(
            id=dev.id,
            name=dev.name,
            platform=dev.platform,
            local_ips=local_list,
            vpn_ips=vpn_list,
            transfer_port=dev.transfer_port,
            is_online=is_active,
            last_seen=dev.last_seen
        ))
    return result

@router.post("/register", response_model=DeviceResponse)
def register_device(
    dev_in: DeviceRegister,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    device = db.query(Device).filter(
        Device.id == dev_in.device_id,
        Device.user_id == current_user.id
    ).first()

    local_json = json.dumps(dev_in.local_ips)
    vpn_json = json.dumps(dev_in.vpn_ips)

    if device:
        device.name = dev_in.name
        device.platform = dev_in.platform
        device.local_ips = local_json
        device.vpn_ips = vpn_json
        device.transfer_port = dev_in.transfer_port
        device.last_seen = datetime.utcnow()
        device.is_online = True
    else:
        device = Device(
            id=dev_in.device_id,
            user_id=current_user.id,
            name=dev_in.name,
            platform=dev_in.platform,
            local_ips=local_json,
            vpn_ips=vpn_json,
            transfer_port=dev_in.transfer_port,
            last_seen=datetime.utcnow(),
            is_online=True
        )
        db.add(device)

    db.commit()
    db.refresh(device)

    return DeviceResponse(
        id=device.id,
        name=device.name,
        platform=device.platform,
        local_ips=dev_in.local_ips,
        vpn_ips=dev_in.vpn_ips,
        transfer_port=device.transfer_port,
        is_online=True,
        last_seen=device.last_seen
    )

@router.post("/{device_id}/heartbeat")
def heartbeat(
    device_id: str,
    hb: DeviceHeartbeat,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    device = db.query(Device).filter(
        Device.id == device_id,
        Device.user_id == current_user.id
    ).first()

    if not device:
        raise HTTPException(status_code=404, detail="Gerät nicht gefunden.")

    device.last_seen = datetime.utcnow()
    device.is_online = True
    device.local_ips = json.dumps(hb.local_ips)
    device.vpn_ips = json.dumps(hb.vpn_ips)
    device.transfer_port = hb.transfer_port

    db.commit()
    return {"status": "ok", "timestamp": device.last_seen}

@router.delete("/{device_id}")
def delete_device(
    device_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    device = db.query(Device).filter(
        Device.id == device_id,
        Device.user_id == current_user.id
    ).first()

    if not device:
        raise HTTPException(status_code=404, detail="Gerät nicht gefunden.")

    db.delete(device)
    db.commit()
    return {"status": "deleted"}

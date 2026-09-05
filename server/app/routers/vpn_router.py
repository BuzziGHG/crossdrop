import json
import logging
from typing import Dict
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, Depends, HTTPException
from sqlalchemy.orm import Session

from app.database import get_db, SessionLocal, Device, User
from app.config import JWT_SECRET, JWT_ALGORITHM
import jwt

router = APIRouter(prefix="/api/vpn", tags=["Automated VPN Tunnel"])
logger = logging.getLogger("crossdrop.vpn")

# In-memory VPN tunnel registry: device_id -> {"ws": WebSocket, "vpn_ip": str, "user_id": int}
active_tunnels: Dict[str, dict] = {}
ip_to_device: Dict[str, str] = {}
next_ip_index = 2

def allocate_vpn_ip(device_id: str) -> str:
    global next_ip_index
    # If device already has an assigned IP, reuse it
    if device_id in active_tunnels:
        return active_tunnels[device_id]["vpn_ip"]

    # Assign from 10.42.0.X pool
    assigned_ip = f"10.42.0.{next_ip_index}"
    next_ip_index += 1
    if next_ip_index > 254:
        next_ip_index = 2
    return assigned_ip

@router.websocket("/tunnel")
async def vpn_tunnel_endpoint(
    websocket: WebSocket,
    token: str = Query(...),
    device_id: str = Query(...)
):
    # 1. Validate JWT Token
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        user_id = int(payload.get("sub"))
    except Exception as e:
        await websocket.close(code=4001, reason="Ungültiges Token")
        return

    await websocket.accept()

    # 2. Allocate Virtual VPN IP
    vpn_ip = allocate_vpn_ip(device_id)

    # Fetch user email for secure stamping
    db = SessionLocal()
    user_email = "Unbekannt"
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if user:
            user_email = user.email
    except Exception as ex:
        logger.error(f"Error fetching user: {ex}")
    finally:
        db.close()

    active_tunnels[device_id] = {
        "ws": websocket,
        "vpn_ip": vpn_ip,
        "user_id": user_id,
        "email": user_email
    }
    ip_to_device[vpn_ip] = device_id

    # 3. Update Device in Database
    db = SessionLocal()
    try:
        device = db.query(Device).filter(Device.id == device_id).first()
        if device:
            device.vpn_ips = json.dumps([vpn_ip])
            device.is_online = True
            db.commit()
    except Exception as ex:
        logger.error(f"Error updating device vpn ip: {ex}")
    finally:
        db.close()

    # 4. Notify Client about successful VPN Connection
    await websocket.send_json({
        "type": "vpn_connected",
        "assigned_ip": vpn_ip,
        "server_ip": "10.42.0.1",
        "status": "connected",
        "message": "Zero-Config VPN Tunnel erfolgreich hergestellt"
    })

    # 5. Handle Tunnel Packet & Data Forwarding
    try:
        while True:
            raw_data = await websocket.receive_text()
            data = json.loads(raw_data)
            
            target_device_id = data.get("target_device_id")
            target_ip = data.get("target_ip")
            
            if target_ip and target_ip in ip_to_device:
                target_device_id = ip_to_device[target_ip]

            if target_device_id and target_device_id in active_tunnels:
                target_tunnel = active_tunnels[target_device_id]
                msg_type = data.get("type")

                is_same_user = (target_tunnel["user_id"] == user_id)
                is_cross_allowed = msg_type in (
                    "transfer_request",
                    "transfer_rejected",
                    "relay_ready",
                    "relay_receiver_progress",
                    "relay_finished"
                )

                if is_same_user:
                    await target_tunnel["ws"].send_text(raw_data)
                elif is_cross_allowed:
                    if msg_type == "transfer_request":
                        data["sender_email"] = active_tunnels.get(device_id, {}).get("email", user_email)
                        data["is_cross_account"] = True
                        await target_tunnel["ws"].send_text(json.dumps(data))
                    else:
                        await target_tunnel["ws"].send_text(raw_data)
                else:
                    await websocket.send_json({"type": "error", "message": "Zugriff verweigert"})
            else:
                await websocket.send_json({
                    "type": "target_offline",
                    "target": target_device_id or target_ip,
                    "message": "Zielgerät ist aktuell nicht im VPN-Tunnel online"
                })
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f"Tunnel exception: {e}")
    finally:
        active_tunnels.pop(device_id, None)
        ip_to_device.pop(vpn_ip, None)
        # Update status in db
        db = SessionLocal()
        try:
            device = db.query(Device).filter(Device.id == device_id).first()
            if device:
                device.is_online = False
                db.commit()
        except Exception:
            pass
        finally:
            db.close()

from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, EmailStr, Field

class UserRegister(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6)

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    email: str
    username: str

class UserResponse(BaseModel):
    id: int
    email: str
    username: str
    created_at: datetime

    class Config:
        from_attributes = True

class DeviceRegister(BaseModel):
    device_id: str
    name: str
    platform: str # "windows", "linux", "android"
    local_ips: List[str] = []
    vpn_ips: List[str] = []
    transfer_port: int = 52520

class DeviceHeartbeat(BaseModel):
    local_ips: List[str] = []
    vpn_ips: List[str] = []
    transfer_port: int = 52520

class DeviceResponse(BaseModel):
    id: str
    name: str
    platform: str
    local_ips: List[str]
    vpn_ips: List[str]
    transfer_port: int
    is_online: bool
    last_seen: datetime

    class Config:
        from_attributes = True

class TransferSignal(BaseModel):
    sender_device_id: str
    target_device_id: str
    filename: str
    file_size: int
    checksum_sha256: Optional[str] = None
    connection_mode: str = "lan" # "lan" or "vpn"

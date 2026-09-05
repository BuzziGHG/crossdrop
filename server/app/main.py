from datetime import datetime
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import init_db
from app.routers import auth_router, device_router, transfer_router, vpn_router, admin_router

app = FastAPI(
    title="CrossDrop Self-Hosted API",
    version="1.0.0",
    description="Account-, Geräte- und Zero-Config VPN-Server für CrossDrop (Windows, Linux, Android)."
)

# Allow all origins so mobile & desktop clients can communicate without CORS issues
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database schema on startup
@app.on_event("startup")
def on_startup():
    init_db()

# Include routers
app.include_router(auth_router.router)
app.include_router(device_router.router)
app.include_router(transfer_router.router)
app.include_router(vpn_router.router)
app.include_router(admin_router.router)

@app.get("/")
def root():
    return {
        "service": "CrossDrop Server",
        "status": "online",
        "vpn_tunnel_support": "active",
        "admin_dashboard": "/admin",
        "docs_url": "/docs",
        "time": datetime.utcnow()
    }

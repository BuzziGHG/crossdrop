import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./crossdrop.db")
JWT_SECRET = os.getenv("JWT_SECRET", "super-secret-key-please-change-in-production-abcdef123456")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = int(os.getenv("ACCESS_TOKEN_EXPIRE_DAYS", "365"))

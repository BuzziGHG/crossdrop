FROM python:3.11-slim

WORKDIR /app

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# Environment variables with defaults
ENV DATABASE_URL="sqlite:////data/crossdrop.db"
ENV JWT_SECRET="change-this-secret-key-in-production-12345"
ENV PORT=2603

# Create volume mount directory for SQLite persistence
RUN mkdir -p /data

EXPOSE 2603

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "2603"]

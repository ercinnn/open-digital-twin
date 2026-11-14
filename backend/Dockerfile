# Open Digital Twin backend: FastAPI + trimesh/ifcopenshell/cascadio + Headless Blender 4.2 LTS.
# Built by Hugging Face Spaces (Docker SDK, port 7860); runs anywhere that runs containers.
# Configuration comes from environment variables / Space secrets:
#   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (secret), CORS_ORIGINS, CORS_ORIGIN_REGEX
FROM python:3.11-slim

ARG BLENDER_VERSION=4.2.23
ARG BLENDER_SERIES=4.2

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Shared libraries Blender needs even in --background mode.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
      libgl1 libegl1 libglib2.0-0 libgomp1 \
      libx11-6 libxext6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 libice6 \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://download.blender.org/release/Blender${BLENDER_SERIES}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
      | tar -xJ -C /opt \
 && ln -s "/opt/blender-${BLENDER_VERSION}-linux-x64/blender" /usr/local/bin/blender \
 && blender --version | head -n 1

# Hugging Face Spaces runs the container as uid 1000.
RUN useradd -m -u 1000 user
WORKDIR /home/user/app

COPY --chown=user requirements.txt .
RUN pip install -r requirements.txt

COPY --chown=user app ./app

USER user
ENV HOME=/home/user \
    BLENDER_PATH=/usr/local/bin/blender \
    PORT=7860

EXPOSE 7860
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]

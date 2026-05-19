# Build arguments
ARG RUNPOD_VERSION=1.0.2
ARG CUDA_VERSION=cu1281
ARG TORCH_VERSION=torch280
ARG UBUNTU_VERSION=ubuntu2404

# =============================================================================
# Builder stage - clone repos and extract requirements
# =============================================================================
FROM alpine/git AS builder

ARG COMFYUI_REQUIREMENTS_SHA=latest

WORKDIR /build

RUN echo "ComfyUI requirements SHA: ${COMFYUI_REQUIREMENTS_SHA}" && \
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git

# =============================================================================
# Final stage - install dependencies
# =============================================================================
FROM runpod/pytorch:${RUNPOD_VERSION}-${CUDA_VERSION}-${TORCH_VERSION}-${UBUNTU_VERSION}

# Permet de voir les logs Python en temps réel dans la console RunPod
ENV PYTHONUNBUFFERED=1

ARG SAGE_ATTENTION_VERSION=2.2.0
ARG CUDA_VERSION=cu1281
ARG TORCH_VERSION=torch280
ARG COMPUTE_CAP=86
ARG PYTHON_VERSION=cp312

WORKDIR /tmp

# 1. Installation des dépendances système (CRITIQUE pour OpenCV et Vidéo)
USER root
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    wget \
    git \
    && rm -rf /var/lib/apt/lists/*

# 2. Mise à jour pip et outils de base
RUN pip install --upgrade setuptools pip

# 3. Installation des dépendances Python lourdes (Nodes + Sage)
# J'ai ajouté ici les libs demandées par KJNodes et VideoHelperSuite
RUN pip install --no-cache-dir \
    cupy-cuda12x \
    triton \
    git+https://github.com/thu-ml/SageAttention.git \
    opencv-python-headless \
    scipy \
    einops \
    tqdm \
    huggingface-hub

# 4. Installation des requirements ComfyUI (depuis le builder stage)
COPY --from=builder /build/ComfyUI-Manager/requirements.txt /tmp/manager-requirements.txt
RUN pip --no-cache-dir install -r manager-requirements.txt

COPY --from=builder /build/ComfyUI/requirements.txt /tmp/comfyui-requirements.txt
RUN pip --no-cache-dir install -r comfyui-requirements.txt

# Nettoyage
RUN rm -rf /tmp/*.txt /root/.cache/pip

# 5. Script de démarrage
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8888 8188

CMD ["/start.sh"]

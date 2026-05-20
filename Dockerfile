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
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/stuttlepress/ComfyUI-Wan-VACE-Prep.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    git clone --depth 1 https://github.com/StableLlama/ComfyUI-basic_data_handling.git && \
    git clone --depth 1 https://github.com/Smirnov75/ComfyUI-mxToolkit.git

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
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    ffmpeg \
    wget \
    git \
    aria2 \
    && rm -rf /var/lib/apt/lists/*

# 2. Mise à jour pip et outils de base
RUN pip install --upgrade setuptools pip uv

# 3. Installation des dépendances Python
RUN uv pip install --system --no-cache \
    cupy-cuda12x \
    triton \
    opencv-python-headless \
    scipy \
    einops \
    tqdm \
    huggingface-hub

RUN uv pip install --system --no-cache \
    https://github.com/Kace54/comfyui-sage-wanvace/releases/download/v2.2.0/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl

# 4. Installation des requirements ComfyUI (depuis le builder stage)
# COPY --from=builder /build /tmp/build_stage
# RUN find /tmp/build_stage -maxdepth 2 -name "requirements.txt" -exec uv pip install --system --no-cache -r {} \;

# Nettoyage
# RUN rm -rf /tmp/build_stage /root/.cache/pip /root/.cache/uv

# 5. Script de démarrage
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22 8888 8188

CMD ["/start.sh"]

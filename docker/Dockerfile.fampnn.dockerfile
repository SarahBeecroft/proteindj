ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ARG TORCH_ROCM_INDEX=rocm7.0
ARG TORCH_VERSION=2.10.0
ARG TORCHVISION_VERSION=0.25.0
ARG MINIFORGE_VERSION=26.9.4-2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so everything the tool needs must be on PATH/ENV.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    PROTEINDJ_TOOL=fampnn \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND} \
    PATH=/opt/conda/bin:${PATH}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm /tmp/miniforge.sh && \
    mamba install -y -c conda-forge python=3.10 && \
    mamba clean -afy

# Backend-specific: the only place CUDA and ROCm differ.
RUN if [ "$GPU_BACKEND" = "cuda" ]; then \
        pip install "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}"; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" \
            --index-url "https://download.pytorch.org/whl/${TORCH_ROCM_INDEX}"; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

RUN pip install \
        scipy \
        certifi \
        torch-geometric \
        gemmi \
        biopython \
        tqdm \
        natsort \
        omegaconf \
        rdkit \
        einops \
        hydra-core \
        torchtyping \
        dm-tree \
        timm \
        jaxtyping \
        joblib \
        pandas

RUN git clone https://github.com/PapenfussLab/fampnn.git /app/fampnn && \
    git -C /app/fampnn checkout 18363df && \
    pip install -e /app/fampnn

ENV PYTHONPATH=/app/fampnn
WORKDIR /app/fampnn

COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py

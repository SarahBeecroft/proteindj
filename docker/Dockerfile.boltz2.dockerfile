ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ARG TORCH_ROCM_INDEX=rocm7.0
ARG TORCH_VERSION=2.10.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so the venv is activated through PATH.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PROTEINDJ_TOOL=boltz2 \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        python3-dev \
        python3-pip \
        python3-venv \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv

# Backend-specific: the only place CUDA and ROCm differ.
RUN if [ "$GPU_BACKEND" = "cuda" ]; then \
        pip install "torch==${TORCH_VERSION}"; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install "torch==${TORCH_VERSION}" --index-url "https://download.pytorch.org/whl/${TORCH_ROCM_INDEX}"; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

# v2.2.1. The cuEquivariance kernels live in the [cuda] extra, so ROCm installs without it.
RUN git clone https://github.com/jwohlwend/boltz.git /opt/boltz && \
    git -C /opt/boltz checkout cb04aec && \
    if [ "$GPU_BACKEND" = "cuda" ]; then pip install "/opt/boltz[cuda]"; else pip install /opt/boltz; fi

COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py

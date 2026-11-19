ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.9.2-base-ubuntu24.04 AS base-cuda
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
    PYTHONDONTWRITEBYTECODE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    HF_HOME=/cache \
    PROTEINDJ_TOOL=boltzgen \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        gcc \
        git \
        libgl1 \
        procps \
        python3-dev \
        python3-pip \
        python3-venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    pip install --upgrade pip setuptools setuptools_scm wheel

# Backend-specific: the only place CUDA and ROCm differ.
RUN if [ "$GPU_BACKEND" = "cuda" ]; then \
        pip install "torch==${TORCH_VERSION}"; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install "torch==${TORCH_VERSION}" --index-url "https://download.pytorch.org/whl/${TORCH_ROCM_INDEX}"; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

# BoltzGen lists the NVIDIA-only packages as core dependencies, so ROCm strips them.
RUN git clone https://github.com/JoshuaMHardy/boltzgen.git /boltzgen && \
    git -C /boltzgen checkout eaf6639 && \
    if [ "$GPU_BACKEND" = "rocm" ]; then \
        grep -qE '^\s*"(nvidia-ml-py|cuequivariance)' /boltzgen/pyproject.toml && \
        sed -i -E '/^\s*"(nvidia-ml-py|cuequivariance)/d' /boltzgen/pyproject.toml; \
    fi && \
    pip install /boltzgen && \
    mkdir -p /cache

COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py

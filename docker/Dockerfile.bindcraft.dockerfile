ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

# ---- Shared system deps + Miniforge ----
FROM base-${GPU_BACKEND} AS common
ARG MINIFORGE_VERSION=26.9.4-2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so the conda env is installed into base and put on PATH.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/conda/bin:${PATH}

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        libgfortran5 \
        procps \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm /tmp/miniforge.sh

# ---- CUDA environment: jax 0.6.2, matching the v3.0 image ----
FROM common AS build-cuda
COPY envs/bindcraft-cuda.yml /tmp/env.yml
RUN mamba env update -n base -y -f /tmp/env.yml && mamba clean -afy

# ---- ROCm environment: only rocm-jax 0.6.0 wheels exist for ROCm 7 ----
FROM common AS build-rocm
COPY envs/bindcraft-rocm.yml /tmp/env.yml
RUN mamba env update -n base -y -f /tmp/env.yml && mamba clean -afy
ENV JAX_PLATFORMS=rocm,cpu \
    OPENMM_PLATFORM_ORDER=HIP,OpenCL,CPU \
    OPENMM_DEFAULT_PLATFORM=HIP \
    XLA_FLAGS='--xla_gpu_enable_command_buffer= --xla_gpu_autotune_level=0' \
    AMD_COMGR_CACHE_DIR=/tmp/amd_comgr_cache

FROM build-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ENV PROTEINDJ_TOOL=bindcraft \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND}

RUN pip install --no-deps git+https://github.com/sokrypton/ColabDesign.git@8fd167defd1b0f98e29f00584ff4f3987e6935dc

RUN git clone https://github.com/PapenfussLab/FreeBindCraft.git /opt/BindCraft && \
    git -C /opt/BindCraft checkout 7a202e2 && \
    chmod +x /opt/BindCraft/functions/DAlphaBall.gcc \
             /opt/BindCraft/functions/dssp \
             /opt/BindCraft/functions/FASPR \
             /opt/BindCraft/functions/sc

ENV BINDCRAFT_HOME=/opt/BindCraft
WORKDIR /opt/BindCraft

COPY smoke/ /opt/smoke/

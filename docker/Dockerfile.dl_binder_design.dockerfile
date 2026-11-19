ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=6.2.4

FROM nvidia/cuda:12.9.1-base-ubuntu22.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

# ---- CUDA: jax 0.4.38 and torch as shipped in the v3.0 image ----
FROM base-cuda AS build-cuda
ARG DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    UV_LINK_MODE=copy \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        python-is-python3 \
        python3-pip \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install uv && \
    uv pip install --system \
        biopython==1.86 \
        git+https://github.com/NVIDIA/dllogger#egg=dllogger \
        dm-haiku==0.0.15 \
        dm-tree==0.1.9 \
        flax==0.10.4 \
        "jax[cuda12]==0.4.38" \
        ml-collections==1.1.0 \
        ml_dtypes==0.5.3 \
        mock==5.2.0 \
        'numpy<2.0' \
        'openmm[cuda12]==8.5.2' \
        pdbfixer \
        pyfaspr \
        tensorflow==2.20.0 \
        torch==2.13.0 \
        torchvision==0.28.0

# ---- ROCm 6.x: jax 0.4.34 (rocm60 plugin) is the newest jax wheel set for ROCm 6 ----
FROM base-rocm AS build-rocm
ARG DEBIAN_FRONTEND=noninteractive
ARG TORCH_ROCM_INDEX=rocm6.2.4
ENV PIP_NO_CACHE_DIR=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    UV_NO_CACHE=1 \
    UV_LINK_MODE=copy \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    ROCM_PATH=/opt/rocm \
    LD_LIBRARY_PATH=/opt/rocm/lib \
    JAX_PLATFORMS=rocm,cpu \
    XLA_FLAGS='--xla_gpu_enable_command_buffer= --xla_gpu_autotune_level=0' \
    AMD_COMGR_CACHE_DIR=/tmp/amd_comgr_cache \
    PATH=/opt/venv/bin:/opt/rocm/bin:${PATH}

RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        python3-pip \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN pip install uv && uv venv --python /usr/bin/python3.12 /opt/venv

RUN uv pip install \
        biopython==1.86 \
        dm-haiku==0.0.15 \
        dm-tree==0.1.9 \
        flax==0.10.4 \
        ml-collections==1.1.0 \
        ml_dtypes==0.5.3 \
        mock==5.2.0 \
        'numpy<2.0' \
        'openmm[hip6]' \
        pdbfixer \
        pyfaspr \
        tensorflow-cpu==2.20.0

RUN uv pip install --index-url "https://download.pytorch.org/whl/${TORCH_ROCM_INDEX}" \
        torch==2.6.0 \
        torchvision==0.21.0

# Installed last so nothing above replaces them.
RUN uv pip install \
        https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jaxlib-0.4.34-cp312-cp312-manylinux_2_28_x86_64.whl \
        https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jax_rocm60_pjrt-0.4.34-py3-none-manylinux_2_28_x86_64.whl \
        https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jax_rocm60_plugin-0.4.34-cp312-cp312-manylinux_2_28_x86_64.whl \
        https://github.com/ROCm/jax/archive/refs/tags/rocm-jax-v0.4.34.tar.gz

FROM build-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ENV PROTEINDJ_TOOL=dl_binder_design \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND} \
    PYTHONPATH=/dl_binder_design

RUN git clone https://github.com/PapenfussLab/dl_binder_design.git /dl_binder_design && \
    git -C /dl_binder_design checkout f159e83 && \
    git clone https://github.com/dauparas/ProteinMPNN.git /dl_binder_design/ProteinMPNN

WORKDIR /dl_binder_design

COPY smoke/ /opt/smoke/
RUN python3 /opt/smoke/check_torch_backend.py

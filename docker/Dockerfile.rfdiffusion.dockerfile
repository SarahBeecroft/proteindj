ARG GPU_BACKEND=cuda
# Unused: the ROCm base below pins its own ROCm release (7.0.0) through AMD's DGL image.
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.4.1-base-ubuntu22.04 AS base-cuda
FROM rocm/dgl:dgl-2.4.0.amd0_rocm7.0.0_ubuntu22.04_py3.10_pytorch_2.7.1 AS base-rocm

# ---- CUDA: torch 2.4 / DGL 2.4 cu124 wheels ----
FROM base-cuda AS build-cuda
ARG DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    DGLBACKEND=pytorch

RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        python-is-python3 \
        python3-pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/PapenfussLab/RFdiffusion /app/RFdiffusion && \
    git -C /app/RFdiffusion checkout 0938f87

RUN pip install \
        dgl==2.4.0 -f https://data.dgl.ai/wheels/torch-2.4/cu124/repo.html \
        torch==2.4.0 -f https://download.pytorch.org/whl/cu124 \
        e3nn==0.5.8 \
        wandb==0.23.0 \
        pynvml==13.0.1 \
        git+https://github.com/NVIDIA/dllogger#egg=dllogger \
        decorator==5.2.1 \
        hydra-core==1.3.2 \
        pyrsistent==0.20.0 \
        icecream==2.1.8 \
        "jax[cuda12]==0.5.3" \
        dm-haiku==0.0.15 \
        dm-tree==0.1.9 \
        biopython==1.86 \
        ml-collections==1.1.0 \
        tensorflow==2.20.0 \
        /app/RFdiffusion/env/SE3Transformer && \
    pip install /app/RFdiffusion --no-deps

# ---- ROCm: AMD's DGL image ships torch 2.7.1 and DGL 2.4 for ROCm ----
FROM base-rocm AS build-rocm
ARG DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    DGLBACKEND=pytorch \
    AMD_COMGR_CACHE_DIR=/tmp/amd_comgr_cache

RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        git \
        procps \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/PapenfussLab/RFdiffusion /app/RFdiffusion && \
    git -C /app/RFdiffusion checkout 0938f87

RUN pip install \
        e3nn==0.5.6 \
        wandb==0.17.0 \
        decorator==5.1.0 \
        hydra-core==1.3.6 \
        pyrsistent==0.19.3 \
        icecream==2.2.0 \
        hiredis==3.4.1 \
        pyarrow==25.0.1 \
        numpy==1.26.4 \
        /app/RFdiffusion/env/SE3Transformer && \
    pip install /app/RFdiffusion --no-deps

FROM build-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ENV PROTEINDJ_TOOL=rfdiffusion \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND}

WORKDIR /app/RFdiffusion

COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py

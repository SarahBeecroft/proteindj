# TEMPLATE: copy to Dockerfile.<tool>.dockerfile and replace every <PLACEHOLDER>.
# Not listed in docker-bake.hcl, so it is never built. See docs/dev/adding_a_new_container.md.
# For tools whose CUDA and ROCm installs share little, use one build stage per backend instead
# (see Dockerfile.bindcraft.dockerfile).

ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM <CUDA_BASE_IMAGE> AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ARG TORCH_ROCM_INDEX=rocm7.0
ARG TORCH_VERSION=2.10.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so everything the tool needs must be on PATH/ENV.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PROTEINDJ_TOOL=<TOOL> \
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
        <EXTRA_APT_PACKAGES> && \
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

# Pin a commit so rebuilds don't silently pick up upstream changes.
RUN git clone <REPO_URL> /app/<TOOL> && \
    git -C /app/<TOOL> checkout <COMMIT_SHA> && \
    pip install /app/<TOOL>

WORKDIR /app/<TOOL>

# Fails the build if a dependency replaced torch with the wrong backend.
COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py

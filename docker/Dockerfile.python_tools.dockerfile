FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so the venv is activated through PATH.
ENV PIP_NO_CACHE_DIR=1 \
    UV_NO_CACHE=1 \
    UV_LINK_MODE=copy \
    PYTHONNOUSERSITE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH} \
    PROTEINDJ_TOOL=python_tools

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        coreutils \
        curl \
        dssp \
        git \
        grep \
        pigz \
        procps \
        python3-dev \
        python3-pip \
        python3-venv \
        sed \
        unzip \
        wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    pip install uv && \
    uv pip install \
        arpeggia \
        biopython \
        matplotlib \
        pandas \
        pdbfixer \
        prodigy-prot \
        pyfaspr \
        pyyaml && \
    uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

COPY smoke/ /opt/smoke/

#!/bin/bash
# GPU-free import and --help checks. Works under docker run and apptainer exec.
# Set SMOKE_GPU=1 on a GPU node (with --nv / --rocm) to also require a visible device.
set -euo pipefail

tool="${PROTEINDJ_TOOL:?PROTEINDJ_TOOL is not set}"
smoke_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Some packages write caches to $HOME, which is read-only or absent in containers.
export NUMBA_CACHE_DIR=/tmp XDG_CONFIG_HOME=/tmp TRITON_CACHE_DIR=/tmp MPLCONFIGDIR=/tmp

check_torch() {
    python "${smoke_dir}/check_torch_backend.py"
    if [[ "${SMOKE_GPU:-0}" == 1 ]]; then
        python -c "import torch; assert torch.cuda.is_available(), 'no GPU visible to torch'"
    fi
}

check_jax() {
    python -c "import jax; print('jax', jax.__version__)"
    if [[ "${SMOKE_GPU:-0}" == 1 ]]; then
        python -c "import jax; assert any(d.platform != 'cpu' for d in jax.devices()), 'no GPU visible to jax'"
    fi
}

echo "Smoke testing ${tool} (${PROTEINDJ_GPU_BACKEND:-cpu})"

case "${tool}" in
    python_tools)
        command -v mkdssp
        python -c "import Bio, pandas, matplotlib, yaml, pdbfixer, torch"
        pip show arpeggia prodigy-prot pyfaspr > /dev/null
        ;;
    boltz2)
        check_torch
        boltz --help > /dev/null
        ;;
    boltzgen)
        check_torch
        boltzgen --help > /dev/null
        ;;
    fampnn)
        check_torch
        pip show fampnn > /dev/null
        python -c "import fampnn, torch_geometric, rdkit"
        ;;
    bindcraft)
        check_jax
        python -c "import colabdesign, openmm, freesasa, pdbfixer"
        test -f /opt/BindCraft/bindcraft.py
        ;;
    dl_binder_design)
        check_torch
        check_jax
        python -c "import haiku, openmm"
        python3 /dl_binder_design/af2_initial_guess/predict.py --help > /dev/null
        python3 /dl_binder_design/mpnn_fr/dl_interface_design_multi.py --help > /dev/null
        ;;
    rfdiffusion)
        check_torch
        python -c "import dgl"
        python /app/RFdiffusion/scripts/run_inference.py --help > /dev/null
        ;;
    *)
        echo "Unknown tool: ${tool}" >&2
        exit 1
        ;;
esac

echo "${tool}: OK"

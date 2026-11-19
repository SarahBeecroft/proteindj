"""Exit non-zero if the installed torch build does not match PROTEINDJ_GPU_BACKEND."""
import os
import sys

import torch

backend = os.environ.get("PROTEINDJ_GPU_BACKEND", "")
runtime = {"cuda": torch.version.cuda, "rocm": torch.version.hip}
if not runtime.get(backend):
    sys.exit(f"torch {torch.__version__} is not a '{backend}' build")
print(f"torch {torch.__version__} OK for {backend}; GPU visible: {torch.cuda.is_available()}")

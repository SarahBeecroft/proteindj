variable "REGISTRY" {
  default = "ghcr.io/hardylaboratory/proteindj"
}

variable "VERSION" {
  default = "v3.1"
}

# One ROCm 6.x (jax 0.4.x wheels) and one ROCm 7.x release across all images.
variable "ROCM6_VERSION" {
  default = "6.2.4"
}

variable "ROCM7_VERSION" {
  default = "7.0.2"
}

variable "TORCH_ROCM6_INDEX" {
  default = "rocm6.2.4"
}

variable "TORCH_ROCM7_INDEX" {
  default = "rocm7.0"
}

variable "SOURCE_URL" {
  default = "https://github.com/hardylaboratory/proteindj"
}

group "default" {
  targets = [
    "python_tools",
    "bindcraft-cuda", "bindcraft-rocm",
    "boltz2-cuda", "boltz2-rocm",
    "boltzgen-cuda", "boltzgen-rocm",
    "dl_binder_design-cuda", "dl_binder_design-rocm",
    "fampnn-cuda", "fampnn-rocm",
    "rfdiffusion-cuda", "rfdiffusion-rocm",
  ]
}

# CPU-only, so it has no backend suffix.
target "python_tools" {
  dockerfile = "Dockerfile.python_tools.dockerfile"
  tags       = ["${REGISTRY}/python_tools:${VERSION}"]
  platforms  = ["linux/amd64"]
  labels = {
    "org.opencontainers.image.source"  = SOURCE_URL
    "org.opencontainers.image.version" = VERSION
  }
}

target "gpu" {
  name = "${tool}-${backend}"
  matrix = {
    tool    = ["bindcraft", "boltz2", "boltzgen", "dl_binder_design", "fampnn", "rfdiffusion"]
    backend = ["cuda", "rocm"]
  }
  dockerfile = "Dockerfile.${tool}.dockerfile"
  args = {
    GPU_BACKEND      = backend
    ROCM_VERSION     = tool == "dl_binder_design" ? ROCM6_VERSION : ROCM7_VERSION
    TORCH_ROCM_INDEX = tool == "dl_binder_design" ? TORCH_ROCM6_INDEX : TORCH_ROCM7_INDEX
  }
  tags      = ["${REGISTRY}/${tool}:${VERSION}-${backend}"]
  platforms = ["linux/amd64"]
  labels = {
    "org.opencontainers.image.source"  = SOURCE_URL
    "org.opencontainers.image.version" = VERSION
  }
}

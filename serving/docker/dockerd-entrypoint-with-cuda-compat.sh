#!/bin/bash
#set -e

verlte() {
    [ "$1" = "$2" ] && return 1 || [ "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}

# Takes 2 environment variables: SM/TGI env var name, LMI env var name
# If SM/TGI env var is set, and LMI env var is unset, set LMI env var to SM/TGI env var value.
translateTGIToLMI() {
  local tgiVal="${!1}"
  local lmiVal="${!2}"
  if [ -n "$tgiVal" ]; then
    export "$2"=${lmiVal:-$tgiVal}
  fi
}

# Follow https://docs.aws.amazon.com/sagemaker/latest/dg/inference-gpu-drivers.html
if [ -f /usr/local/cuda/compat/libcuda.so.1 ]; then
    CUDA_COMPAT_MAX_DRIVER_VERSION=$(readlink /usr/local/cuda/compat/libcuda.so.1 |cut -d'.' -f 3-)
    echo "CUDA compat package requires Nvidia driver ⩽${CUDA_COMPAT_MAX_DRIVER_VERSION}"
    NVIDIA_DRIVER_VERSION=$(sed -n 's/^NVRM.*Kernel Module *\([0-9.]*\).*$/\1/p' /proc/driver/nvidia/version 2>/dev/null || true)
    echo "Current installed Nvidia driver version is ${NVIDIA_DRIVER_VERSION}"
    if verlte $NVIDIA_DRIVER_VERSION $CUDA_COMPAT_MAX_DRIVER_VERSION; then
        echo "Setup CUDA compatibility libs path to LD_LIBRARY_PATH"
        export LD_LIBRARY_PATH=/usr/local/cuda/compat:$LD_LIBRARY_PATH
        echo $LD_LIBRARY_PATH
    else
        echo "Skip CUDA compat libs setup as newer Nvidia driver is installed"
    fi
else
    echo "Skip CUDA compat libs setup as package not found"
fi

# Convert select SM/TGI Environment Variables to LMI Equivalents
translateTGIToLMI "HF_MODEL_QUANTIZE" "OPTION_QUANTIZE"
# We use HF_TRUST_REMOTE_CODE in our properties parsing
translateTGIToLMI "HF_MODEL_TRUST_REMOTE_CODE" "HF_TRUST_REMOTE_CODE"
translateTGIToLMI "SM_NUM_GPUS" "TENSOR_PARALLEL_DEGREE"
translateTGIToLMI "MAX_CONCURRENT_REQUESTS" "SERVING_JOB_QUEUE_SIZE"
translateTGIToLMI "MAX_BATCH_PREFILL_TOKENS" "OPTION_MAX_ROLLING_BATCH_PREFILL_TOKENS"
translateTGIToLMI "MAX_BATCH_SIZE" "OPTION_MAX_ROLLING_BATCH_SIZE"

if [[ "$1" = "serve" ]]; then
    shift 1
    code=77
    while [[ code -eq 77 ]]
    do
        /usr/bin/djl-serving "$@"
        code=$?
    done
elif [[ "$1" = "partition" ]] || [[ "$1" = "train" ]]; then
    shift 1
    /usr/bin/python3 /opt/djl/partition/partition.py "$@"
else
    eval "$@"
fi

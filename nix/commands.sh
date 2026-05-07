#!/usr/bin/env bash
# Lists the AutoRound dev-shell commands. Mirrors the shellHook banner
# in flake.nix but is callable on demand from the prompt.
set -euo pipefail

cat <<'EOF'
auto-round XPU dev environment — available commands

  quantize <model> <type>                      # B70-tuned wrapper. types: int4 int8 mxfp4 nvfp4 gguf:q4_k_m ...
  quantize help                                # full quantize help (env vars, examples)

  autoround <model>                            # raw wrapper (default: auto-round-light, low_gpu_mem ON)
  autoround quantize <model> [flags...]        # explicit form
  autoround shell                              # interactive shell inside the XPU container
  autoround run -- <cmd...>                    # arbitrary command inside the container
  autoround build                              # rebuild image (--no-cache)
  autoround pull                               # pull base image only
  autoround help                               # full autoround help

  auto-round-qwen-3-6-35b-a3b safe             # bs=4 ga=2 + drop low_gpu_mem (~5h, ~29 GB)
  auto-round-qwen-3-6-35b-a3b aggressive       # bs=8 ga=1 + drop low_gpu_mem (~4h, 29.36 GB MEASURED)
  auto-round-qwen-3-6-35b-a3b help             # tuned recipe presets for Qwen3.6-35B-A3B

  commands                                     # this listing

Quick start for the AEON Qwen3.6-27B dense model:
  quantize AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-BF16 int4

EOF

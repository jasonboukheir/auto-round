#!/usr/bin/env bash
# General-purpose AutoRound wrapper with B70-tuned defaults.
# Usage: quantize <model> <type> [extra auto-round flags...]
set -euo pipefail

RECIPE_BIN="${AUTOROUND_QUANTIZE_RECIPE:-auto-round}"
SEQLEN="${AUTOROUND_QUANTIZE_SEQLEN:-2048}"
BATCH_SIZE="${AUTOROUND_QUANTIZE_BS:-4}"
GRAD_ACCUM="${AUTOROUND_QUANTIZE_GA:-2}"
FORMAT="${AUTOROUND_QUANTIZE_FORMAT:-auto_round}"

usage() {
    cat <<'EOF'
quantize — B70-tuned AutoRound wrapper

Usage:
  quantize <model> <type> [extra auto-round flags...]
  quantize help

Arguments:
  <model>   HuggingFace model id or local path (e.g. AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-BF16)
  <type>    Quantization scheme. Maps to auto-round --scheme:
              int4    -> W4A16   (4-bit sym weights, fp16 act, group_size=128)  default
              int8    -> W8A16   (8-bit sym weights, fp16 act)
              int2    -> W2A16   (2-bit sym weights, fp16 act — quality risk)
              w4a16   -> W4A16   (alias)
              w8a16   -> W8A16   (alias)
              mxfp4   -> MXFP4   (microscaling fp4)
              nvfp4   -> NVFP4   (NVIDIA fp4)
              gguf:q4_k_m -> GGUF Q4_K_M (llama.cpp)
              gguf:q5_k_m -> GGUF Q5_K_M

Tuned defaults (Battlemage B70 30 GB, dense + hybrid-MoE friendly):
  recipe              auto-round           200 iters, full quality
  batch_size          4
  gradient_accumulate 2                    bs=4 ga=2 = 1.51x faster than bs=1 ga=8 at matched tokens
  seqlen              2048
  low_gpu_mem_usage   OFF                  +1.30x speed at +53% VRAM (still fits dense <=35B)
  torch_compile       OFF                  measured 1.57x SLOWER on dense
  format              auto_round           vLLM/SGLang-compatible
  device              0                    first XPU
  output_dir          /output (container)  -> $AUTOROUND_OUTPUT_DIR on host

Examples:
  quantize AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-BF16 int4
  quantize Qwen/Qwen3.6-35B-A3B int4 --to_quant_block_names 'model\.language_model\.layers\.0$'
  quantize meta-llama/Llama-3.1-8B int8

Environment overrides:
  AUTOROUND_QUANTIZE_RECIPE   auto-round | auto-round-light | auto-round-best   (default: auto-round)
                              light = 50 iters (~3-4x faster, ~1.3-2x higher per-block MSE)
                              best  = 1000 iters (multi-day; rarely worth it)
  AUTOROUND_QUANTIZE_SEQLEN   calibration seqlen   (default: 2048)
  AUTOROUND_QUANTIZE_BS       per-step batch size  (default: 4)
  AUTOROUND_QUANTIZE_GA       gradient accumulate  (default: 2)
  AUTOROUND_QUANTIZE_FORMAT   auto_round | auto_gptq | auto_awq | gguf:* | llm_compressor   (default: auto_round)
  AUTOROUND_OUTPUT_DIR        host output dir base (default: $PWD/output)

Why these defaults: see `auto-round-qwen-3-6-35b-a3b help` for the full per-knob
decomposition (Qwen3-0.6B dense smokes + Qwen3.6-35B-A3B verification on B70).

EOF
}

scheme_for_type() {
    local raw="$1"
    local lower
    lower="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        int4|w4a16)  echo "W4A16" ;;
        int8|w8a16)  echo "W8A16" ;;
        int2|w2a16)  echo "W2A16" ;;
        int3|w3a16)  echo "W3A16" ;;
        mxfp4)       echo "MXFP4" ;;
        mxfp8)       echo "MXFP8" ;;
        nvfp4)       echo "NVFP4" ;;
        fp8|fp8_static) echo "FP8_STATIC" ;;
        gguf:*)
            local gguf_type="${lower#gguf:}"
            printf 'GGUF:%s' "$(printf '%s' "$gguf_type" | tr '[:lower:]' '[:upper:]')"
            ;;
        *) return 1 ;;
    esac
}

format_for_scheme() {
    local scheme="$1"
    case "$scheme" in
        GGUF:*) printf 'gguf:%s' "$(printf '%s' "${scheme#GGUF:}" | tr '[:upper:]' '[:lower:]')" ;;
        *)      echo "$FORMAT" ;;
    esac
}

main() {
    local first="${1:-}"
    case "$first" in
        ""|-h|--help|help) usage; exit 0 ;;
    esac

    if [[ $# -lt 2 ]]; then
        echo "error: missing arguments. Need <model> and <type>." >&2
        echo "" >&2
        usage >&2
        exit 1
    fi

    local model="$1"; shift
    local type_arg="$1"; shift

    local scheme
    scheme="$(scheme_for_type "$type_arg" || true)"
    if [[ -z "$scheme" ]]; then
        echo "error: unknown quantization type '$type_arg'" >&2
        echo "       supported: int4 int8 int2 int3 w4a16 w8a16 mxfp4 mxfp8 nvfp4 fp8 gguf:q4_k_m gguf:q5_k_m ..." >&2
        exit 1
    fi

    local fmt
    fmt="$(format_for_scheme "$scheme")"

    echo ">>> quantize $model -> $scheme (format=$fmt)"
    echo ">>> recipe=$RECIPE_BIN bs=$BATCH_SIZE ga=$GRAD_ACCUM seqlen=$SEQLEN low_gpu_mem=OFF compile=OFF"
    echo ""

    exec autoround run -- "$RECIPE_BIN" \
        --model "$model" \
        --scheme "$scheme" \
        --format "$fmt" \
        --device 0 \
        --batch_size "$BATCH_SIZE" \
        --gradient_accumulate_steps "$GRAD_ACCUM" \
        --seqlen "$SEQLEN" \
        --output_dir /output \
        "$@"
}

main "$@"

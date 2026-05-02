{
  description = "AutoRound XPU quantization toolkit (podman-wrapped)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        containerfile = ./nix/Containerfile;
        # Build context only needs the Containerfile; nothing else is COPY'd.
        # Using ./nix limits what podman tar's up.
        buildContext = ./nix;
        autoroundScript = ./nix/autoround.sh;
        qwen35bScript = ./nix/auto-round-qwen-3-6-35b-a3b.sh;

        runtimeInputs = [
          pkgs.podman
          pkgs.skopeo
          pkgs.jq
          pkgs.curl
          pkgs.gawk
        ];

        # The host-facing `autoround` command. Embeds container-build
        # paths via env vars so the script works from any CWD (e.g. when
        # invoked via `nix run` from outside the project).
        autoround = pkgs.writeShellApplication {
          name = "autoround";
          runtimeInputs = runtimeInputs;
          text = ''
            export AUTOROUND_CONTAINERFILE="${containerfile}"
            export AUTOROUND_BUILD_CONTEXT="${buildContext}"
            exec bash "${autoroundScript}" "$@"
          '';
        };

        # Recipe-preset wrapper for Qwen3.6-35B-A3B. Calls `autoround` under
        # the hood and exposes safe/aggressive presets tuned from per-knob
        # measurements on B70 (see `auto-round-qwen-3-6-35b-a3b help`).
        qwen35b = pkgs.writeShellApplication {
          name = "auto-round-qwen-3-6-35b-a3b";
          runtimeInputs = [ autoround ];
          text = ''exec bash "${qwen35bScript}" "$@"'';
        };

      in {
        packages = {
          inherit autoround qwen35b;
          default = autoround;
        };

        apps = {
          default = flake-utils.lib.mkApp { drv = autoround; };
          autoround = flake-utils.lib.mkApp { drv = autoround; };
          qwen-3-6-35b-a3b = flake-utils.lib.mkApp { drv = qwen35b; };
        };

        devShells.default = pkgs.mkShell {
          name = "auto-round-xpu-dev";
          packages = runtimeInputs ++ [
            autoround
            qwen35b
            pkgs.dive
            pkgs.level-zero
            pkgs.intel-compute-runtime
            pkgs.clinfo
            pkgs.pciutils
          ];

          shellHook = ''
            # Live source overlay: the wrapper mounts $AUTOROUND_SOURCE_DIR
            # at /workspace and sets PYTHONPATH=/workspace, so edits to the
            # auto-round repo show up in the next container run without an
            # image rebuild.
            export AUTOROUND_SOURCE_DIR="$PWD"
            export AUTOROUND_OUTPUT_DIR="''${AUTOROUND_OUTPUT_DIR:-$PWD/output}"

            echo "auto-round XPU dev environment"
            echo ""
            echo "  autoround <model>                            # quantize (W4A16 auto-round-light, vLLM-ready)"
            echo "  autoround shell                              # interactive shell inside container"
            echo "  autoround run -- <cmd>                       # arbitrary command inside container"
            echo "  autoround build                              # rebuild image (--no-cache)"
            echo ""
            echo "  auto-round-qwen-3-6-35b-a3b help             # tuned recipe presets for Qwen3.6-35B-A3B"
            echo "  auto-round-qwen-3-6-35b-a3b safe             # bs=4 ga=2 + drop low_gpu_mem (~5h, ~29 GB)"
            echo "  auto-round-qwen-3-6-35b-a3b aggressive       # bs=8 ga=1 + drop low_gpu_mem (~4h, may OOM)"
            echo ""
            echo "  source overlay : $AUTOROUND_SOURCE_DIR -> /workspace (PYTHONPATH)"
            echo "  output dir     : $AUTOROUND_OUTPUT_DIR"
            echo ""
            echo "First run builds localhost/auto-round-xpu:latest (intel/vllm:0.17.0-xpu + auto-round)."
          '';
        };

        checks.smoke = pkgs.runCommand "auto-round-xpu-smoke"
          { nativeBuildInputs = [ pkgs.bash pkgs.shellcheck ]; }
          ''
            echo "--- bash -n ---"
            bash -n ${autoroundScript}
            bash -n ${qwen35bScript}
            echo "--- shellcheck ---"
            shellcheck ${autoroundScript} || true
            shellcheck ${qwen35bScript} || true
            touch $out
          '';
      });
}

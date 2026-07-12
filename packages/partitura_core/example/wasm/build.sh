#!/usr/bin/env bash
# Compiles partitura_core to WebAssembly (dart2wasm / WasmGC).
#
#   ./build.sh          # build both entry points into ./build/
#   node run_node.mjs   # run the smoke as WASM under Node
#   (serve this dir over http and open index.html for the browser demo)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

echo "→ wasm_smoke.dart (asset-free codec smoke)"
dart compile wasm wasm_smoke.dart -o build/wasm_smoke.wasm

echo "→ main.dart (browser js-interop demo)"
dart compile wasm main.dart -o build/main.wasm

echo "done → build/  (run 'node run_node.mjs', or serve index.html over http)"

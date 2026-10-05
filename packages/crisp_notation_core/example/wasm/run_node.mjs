// Runs the WASM-compiled smoke (wasm_smoke.dart) under Node — proof that
// crisp_notation_core executes as WebAssembly, not just that it compiles.
//
//   ./build.sh && node run_node.mjs
//
// The .mjs loader is emitted by `dart compile wasm` next to the .wasm module.
import { readFileSync } from 'node:fs';
// The loader's CompiledApp API (compile → instantiate → invokeMain); the
// free `instantiate`/`invoke` exports were removed from dart2wasm's output in
// Dart 3.13 (Flutter 3.47).
import { compile } from './build/wasm_smoke.mjs';

const bytes = readFileSync(new URL('./build/wasm_smoke.wasm', import.meta.url));
const app = await compile(new Uint8Array(bytes));
const instance = await app.instantiate({});
instance.invokeMain();

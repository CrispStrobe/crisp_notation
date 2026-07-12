// Runs the WASM-compiled smoke (wasm_smoke.dart) under Node — proof that
// partitura_core executes as WebAssembly, not just that it compiles.
//
//   ./build.sh && node run_node.mjs
//
// The .mjs loader is emitted by `dart compile wasm` next to the .wasm module.
import { readFileSync } from 'node:fs';
import { compile, instantiate, invoke } from './build/wasm_smoke.mjs';

const bytes = readFileSync(new URL('./build/wasm_smoke.wasm', import.meta.url));
const module = await compile(new Uint8Array(bytes));
const instance = await instantiate(Promise.resolve(module), Promise.resolve({}));
invoke(instance);

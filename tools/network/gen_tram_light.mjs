// Compatibility entry point: shared signal authoring now uses the Python packer.
// Never overwrite scene/parts files: existing placements and archived references stay intact.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const source = fileURLToPath(new URL("../godot_export/build_signals.py", import.meta.url));
const result = spawnSync("python3", [source, ...process.argv.slice(2)], { stdio: "inherit" });
if (result.error) throw result.error;
process.exit(result.status ?? 1);

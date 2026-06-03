#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_config="$script_dir/Romestead.runtimeconfig.json"
loader_path="$script_dir/BepInEx.NET.CoreCLR.dll"
loader_deps_path="$script_dir/BepInEx.NET.CoreCLR.deps.json"
core_path="$script_dir/BepInEx/core/BepInEx.Core.dll"
backup="$runtime_config.bepinex-backup"

if [ ! -f "$runtime_config" ]; then
    echo "Romestead.runtimeconfig.json was not found."
    echo "Extract this archive directly into the Romestead game directory, then run ./install.sh again."
    exit 1
fi

if [ ! -f "$loader_path" ]; then
    echo "Loader file is missing: $loader_path"
    exit 1
fi

if [ ! -f "$loader_deps_path" ]; then
    echo "Loader deps file is missing: $loader_deps_path"
    exit 1
fi

if [ ! -f "$core_path" ]; then
    echo "BepInEx core files are missing: $core_path"
    exit 1
fi

if [ ! -f "$backup" ]; then
    cp "$runtime_config" "$backup"
    echo "Backup created: $backup"
fi

python3 - "$runtime_config" "$loader_path" <<'PY'
import json
import pathlib
import sys

runtime_config = pathlib.Path(sys.argv[1])
loader_path = str(pathlib.Path(sys.argv[2]).resolve())

with runtime_config.open("r", encoding="utf-8-sig") as f:
    data = json.load(f)

runtime_options = data.setdefault("runtimeOptions", {})
config_properties = runtime_options.setdefault("configProperties", {})
config_properties["STARTUP_HOOKS"] = loader_path

with runtime_config.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Startup hook set to: {loader_path}")
PY

echo ""
echo "Romestead BepInEx mod loader installed."
echo "Launch the game through Steam."

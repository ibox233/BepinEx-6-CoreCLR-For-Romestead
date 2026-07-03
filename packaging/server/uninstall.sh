#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_config="$script_dir/Server.runtimeconfig.json"
backup="$runtime_config.bepinex-backup"

if [ ! -f "$runtime_config" ]; then
    echo "Server.runtimeconfig.json was not found."
    echo "Run sh uninstall.sh from the Romestead dedicated server directory."
    exit 1
fi

if [ -f "$backup" ]; then
    cp "$backup" "$runtime_config"
    echo "Runtime config restored from: $backup"
else
    python3 - "$runtime_config" <<'PY'
import json
import pathlib
import sys

runtime_config = pathlib.Path(sys.argv[1])

with runtime_config.open("r", encoding="utf-8-sig") as f:
    data = json.load(f)

runtime_options = data.get("runtimeOptions") or {}
config_properties = runtime_options.get("configProperties") or {}
hook_value = str(config_properties.get("STARTUP_HOOKS") or "")

if hook_value.endswith("BepInEx.NET.CoreCLR.dll"):
    config_properties.pop("STARTUP_HOOKS", None)
    with runtime_config.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("Startup hook removed from runtime config.")
else:
    print("No Romestead Server BepInEx STARTUP_HOOKS entry found.")
PY
fi

rm -f "$script_dir/BepInEx.NET.CoreCLR.dll"
rm -f "$script_dir/BepInEx.NET.CoreCLR.deps.json"

echo ""
echo "Loader hook removed. The BepInEx folder was kept so server plugins/configs are not deleted."

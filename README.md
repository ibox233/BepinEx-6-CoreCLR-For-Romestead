# Romestead BepInEx Mod Loader

A Romestead-specific mod loader based on BepInEx 6 BE755 for .NET/CoreCLR.

This modified version of BepInEx for Romestead is created and maintained by
ibox233 (Ice Box Studio). It keeps the familiar BepInEx plugin model, folder
layout, console logging, file logging, and HarmonyX patching workflow, while
narrowing the runtime path to Romestead's .NET 8 / MonoGame Windows build.

It is based on upstream BepInEx commit:

```text
3fab71a1914132a1ce3a545caf3192da603f2258
```

This project is not a full general-purpose BepInEx distribution. Non-CoreCLR
runtime frontends and legacy launcher paths have been removed. The remaining
mod loader starts through Romestead's CoreCLR startup hook path.

## Features

- BepInEx plugin metadata and chainloader model.
- BepInEx-style `BepInEx/plugins`, `BepInEx/config`, and `BepInEx/core`
  layout.
- Console and file logging for real-time startup inspection.
- CoreCLR startup hook entrypoint for Romestead.
- HarmonyX-based runtime patching, updated to HarmonyX `2.16.1`.
- No Romestead game binaries, game assets, Steam files, saves, or logs.
- No Steam ownership check or DRM bypass.

## Installing into Romestead

For normal users, use the release package:

1. In Steam, right-click Romestead.
2. Open `Manage` -> `Browse local files`.
3. Extract the release archive directly into the Romestead game folder.
4. Confirm that `install.bat` is next to `Romestead.exe`.
5. Run `install.bat`.
6. Start Romestead through Steam.

After extraction, the game folder should look like this:

```text
Romestead/
  Romestead.exe
  BepInEx.NET.CoreCLR.dll
  BepInEx.NET.CoreCLR.deps.json
  install.bat
  uninstall.bat
  BepInEx/
    core/
```

Plugin DLLs go here:

```text
Romestead/BepInEx/plugins
```

Logs are written here:

```text
Romestead/BepInEx/LogOutput.log
```

Romestead should still be launched through Steam. Direct `Romestead.exe` or
`dotnet Romestead.dll` launches may hit the game's Steam startup checks.

Steam file verification or a Romestead game update may restore the game's
runtime config and remove the loader hook. If BepInEx stops starting after
either of these, run `install.bat` again from the game folder.

### Manual install from a local build

Build the loader first:

```powershell
dotnet build .\BepInEx.sln -c Release
```

The CoreCLR package is produced under:

```text
bin/NET.CoreCLR/net8.0
```

Copy the CoreCLR output into the game directory in the same shape as a BepInEx
CoreCLR install:

```text
Romestead/
  BepInEx.NET.CoreCLR.dll
  BepInEx.NET.CoreCLR.deps.json
  BepInEx/
    core/
```

Set Romestead's `Romestead.runtimeconfig.json` startup hook to the loader:

```json
"STARTUP_HOOKS": "F:\\SteamLibrary\\steamapps\\common\\romestead\\BepInEx.NET.CoreCLR.dll"
```

The release package installer performs this step automatically.

## Making Romestead Mods

Romestead plugins are standard BepInEx CoreCLR plugins. A typical plugin should
target `net8.0-windows`, reference BepInEx from `BepInEx/core`, reference game
assemblies only for compiling, and output one plugin DLL into
`BepInEx/plugins`.

Suggested project structure:

```text
MyMod/
  MyMod.csproj
  PluginInfo.cs
  MyMod.cs
  Properties/
    AssemblyInfo.cs
  Features/
  Patches/
```

Common compile-time references:

```text
BepInEx/core/BepInEx.Core.dll
BepInEx/core/BepInEx.NET.Common.dll
BepInEx/core/0Harmony.dll
Romestead.dll
CandideServer.dll
Shared.dll
CandideCreator.Shared.dll
MonoGame.Framework.dll
```

Reference the Romestead game DLLs from the local game installation only. Do not
redistribute game DLLs with your mod.

Minimal plugin entrypoint:

```csharp
using System;
using System.Reflection;
using BepInEx;
using BepInEx.Logging;
using BepInEx.NET.Common;
using HarmonyLib;

namespace MyMod
{
    [BepInPlugin(PluginInfo.PLUGIN_GUID, PluginInfo.PLUGIN_NAME, PluginInfo.PLUGIN_VERSION)]
    public class MyMod : BasePlugin
    {
        public static MyMod _Instance;
        public static MyMod Instance => _Instance;
        internal static ManualLogSource Logger { get; private set; }

        private Harmony _harmony;

        public override void Load()
        {
            _Instance = this;
            Logger = Log;

            try
            {
                _harmony = new Harmony(PluginInfo.PLUGIN_GUID);
                _harmony.PatchAll(Assembly.GetExecutingAssembly());
            }
            catch (Exception ex)
            {
                Logger.LogError($"{PluginInfo.PLUGIN_NAME} initialization error: {ex.Message}\n{ex.StackTrace}");
            }
        }
    }
}
```

Minimal `PluginInfo.cs`:

```csharp
namespace MyMod
{
    public static class PluginInfo
    {
        public const string PLUGIN_GUID = "YourName.Romestead.MyMod";
        public const string PLUGIN_NAME = "MyMod";
        public const string PLUGIN_VERSION = "1.0.0";
        public const string PLUGIN_AUTHOR = "YourName";
    }
}
```

Minimal HarmonyX patch example:

```csharp
using Candide.GameModels.Managers;
using HarmonyLib;
using Microsoft.Xna.Framework;
using Shared.Models.Construction;

namespace MyMod.Patches.Construction
{
    [HarmonyPatch(typeof(ConstructionSitesManager), "CreateConstructionSite")]
    public static class ConstructionSitesManagerCreateConstructionSitePatch
    {
        [HarmonyPrefix]
        public static void Prefix(ConstructionModel construction, Point tilePosition)
        {
            MyMod.Logger.LogInfo($"Creating construction site: {construction.Id} at {tilePosition}.");
        }
    }
}
```

## Building This Loader

Use the normal BepInEx solution build:

```powershell
dotnet build .\BepInEx.sln -c Release
```

The CoreCLR output is produced under:

```text
bin/NET.CoreCLR/net8.0
```

## Credits

| Project / Role | Credits |
| --- | --- |
| BepInEx | BepInEx team and contributors |
| Romestead-specific modified version | Modified by ibox233 / Ice Box Studio |
| HarmonyX | HarmonyX contributors |
| MonoMod, Mono.Cecil, and other dependencies | Their respective maintainers and contributors |
| Romestead | Romestead's developer and publisher; this project is unofficial and not affiliated with them |

## License

BepInEx is licensed under LGPL-2.1. This modified version preserves the upstream
license and copyright notices.

Third-party dependencies keep their own licenses. Do not publish Romestead game
binaries, game assets, Steam files, generated logs containing local user paths,
or any other copyrighted game content.

See [ROMESTEAD_FORK.md](ROMESTEAD_FORK.md) for additional fork notes and
redistribution guidance.

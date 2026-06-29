# Romestead BepInEx Mod Loader

A Romestead-specific mod loader based on BepInEx 6 BE755 for .NET/CoreCLR.

This modified version of BepInEx for Romestead is created and maintained by
ibox233 (Ice Box Studio). It keeps the familiar BepInEx plugin model, folder
layout, console logging, file logging, and HarmonyX patching workflow, while
narrowing the runtime path to Romestead's .NET 8 / MonoGame build.

It is based on upstream BepInEx commit:

```text
3fab71a1914132a1ce3a545caf3192da603f2258
```

This project is not a full general-purpose BepInEx distribution. Non-CoreCLR
runtime frontends and legacy launcher paths have been removed so the package can
stay focused on Romestead's .NET 8 / MonoGame build.

## Features

- BepInEx plugin metadata and chainloader model.
- BepInEx-style `BepInEx/plugins`, `BepInEx/config`, and `BepInEx/core`
  layout.
- Console and file logging for real-time startup inspection.
- Add-only client installation.
- CoreCLR loading path for Romestead.
- HarmonyX-based runtime patching, updated to HarmonyX `2.16.1`.
- No Romestead game binaries, game assets, Steam files, saves, or logs.
- No Steam ownership check or DRM bypass.

## Installing into Romestead

For normal users, use the release package for your platform.

### Windows

1. In Steam, right-click Romestead.
2. Open `Manage` -> `Browse local files`.
3. Extract the `win-x64` release archive directly into the Romestead game folder.
4. Confirm that the package files are next to `Romestead.exe`.
5. Start Romestead through Steam.

After extracting the Windows package, the game folder should look like this:

```text
Romestead/
  Romestead.exe
  d3d11.dll
  BepInEx.NET.CoreCLR.dll
  BepInEx.NET.CoreCLR.deps.json
  BepInEx/
    core/
```

### Linux

Linux has two distinct cases: the **client** (run through Steam Proton) and a
**dedicated server** (run with `dotnet Server.dll`). They use different loader
init mechanisms - make sure to pick the section that matches what you are running.

#### Linux client (Steam Proton)

Romestead does not currently have a native Linux client build. Use the
`linux-x64` package when running the Romestead client through Steam Proton.

1. In Steam, open Romestead's local files.
2. Extract the `linux-x64` release archive directly into the Romestead game folder.
3. Confirm that the package files are next to `Romestead.exe`.
4. Start Romestead through Steam.

After extracting the Linux package, the game folder should look like this:

```text
Romestead/
  Romestead.exe
  d3d11.dll
  BepInEx.NET.CoreCLR.dll
  BepInEx.NET.CoreCLR.deps.json
  BepInEx/
    core/
```

> The client relies on the `d3d11.dll` hook, which Proton resolves the same way Windows does. Romestead should still be launched through Steam. Direct `Romestead.exe` or `dotnet Romestead.dll` launches may hit the game's Steam startup checks.

#### Linux dedicated server (`dotnet Server.dll`)

The `d3d11.dll` hook does **not** apply to a dedicated server. A headless
`dotnet Server.dll` process never calls into Direct3D, so the d3d11 shim never
fires and BepInEx never loads. The server instead uses the .NET CoreCLR
Startup Hook.

To enable it, edit the server's `Server.runtimeconfig.json` and add a
`STARTUP_HOOKS` entry under `configProperties`, pointing at the absolute path of
`BepInEx.NET.CoreCLR.dll`:

```json
{
  "runtimeOptions": {
    "configProperties": {
      "STARTUP_HOOKS": "/absolute/path/to/server/BepInEx/core/BepInEx.NET.CoreCLR.dll"
    }
  }
}
```

> If `runtimeOptions` or `configProperties` already exist in the file, merge the `STARTUP_HOOKS` key in rather than replacing the whole block.

- Alternatively, you can set `DOTNET_STARTUP_HOOKS` in the environment variables, if you'd rather opt to not edit a Runtime config.

#### Plugins and logs (Linux)

Plugin DLLs go here:

```text
/your/install/path/BepInEx/plugins
```

Logs are written here:

```text
/your/install/path/BepInEx/LogOutput.log
```

### Local build package

For local testing, build a release-style package and install it the same way as
the public release:

```powershell
.\packaging\package-release.ps1 -Configuration Release -Runtime win-x64
```

For the Steam Proton package:

```powershell
.\packaging\package-release.ps1 -Configuration Release -Runtime linux-x64
```

The generated archives are written to:

```text
artifacts/
```

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

# Romestead CoreCLR fork notes

This branch is a game-specific, CoreCLR-only fork of BepInEx BE755 for
Romestead.

The fork is based on upstream BepInEx commit:

```text
3fab71a1914132a1ce3a545caf3192da603f2258
```

Romestead is a .NET 8 / MonoGame Windows game. Stock BepInEx BE755 CoreCLR
assumes Unity-style game paths. This branch keeps the BepInEx plugin model and
directory layout, while narrowing the runtime path to this game.

This is not a full BepInEx distribution. Unity Mono, Unity IL2CPP, Doorstop, and
.NET Framework launcher support have been removed from this fork.

## Changes in this fork

- Targets the CoreCLR startup hook build at `net8.0`.
- Resolves Romestead paths as a non-Unity .NET game, with the game root as the
  managed directory.
- Makes the CoreCLR startup hook idempotent so repeated hook configuration does
  not initialize BepInEx twice.
- Updates HarmonyX to 2.16.1 for plugin patching on this game.
- Removes non-CoreCLR runtime projects and build assets.
- Keeps the BepInEx console and log output behavior so startup can be inspected
  in real time.

## Building

Use the normal BepInEx solution build:

```powershell
dotnet build .\BepInEx.sln -c Release
```

The CoreCLR package is produced under:

```text
bin/NET.CoreCLR/net8.0
```

## Installing into Romestead

Copy the CoreCLR output into the game directory in the same shape as a BepInEx
CoreCLR install:

```text
Romestead/
  BepInEx.NET.CoreCLR.dll
  BepInEx.NET.CoreCLR.deps.json
  BepInEx/
    core/
    plugins/
    config/
    patchers/
```

Set Romestead's `Romestead.runtimeconfig.json` startup hook to the loader:

```json
"STARTUP_HOOKS": "F:\\SteamLibrary\\steamapps\\common\\romestead\\BepInEx.NET.CoreCLR.dll"
```

Romestead should still be launched through Steam. Direct `Romestead.exe` or
`dotnet Romestead.dll` launches may hit the game's Steam startup checks, but
they are useful for short loader smoke tests.

## License and redistribution

BepInEx is licensed under LGPL-2.1. Keep the upstream `LICENSE`, copyright
notices, and source availability intact when distributing this fork.

This fork also redistributes third-party dependencies under their own licenses,
including HarmonyX 2.16.1 and MonoMod / Mono.Cecil components. Keep their NuGet
package license files/notices with binary releases where applicable.

Do not publish Romestead game binaries, game assets, Steam files, or generated
logs containing local user paths. Publish only this modified BepInEx source and
your own plugin/source files.

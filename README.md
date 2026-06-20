# Romestead BepInEx Mod Loader

Romestead-specific BepInEx 6 loader for the game's .NET 8 / MonoGame client.

This fork is based on BepInEx 6 BE764:

```text
5f39645992ab8b944cad394b63470e4920f8b16d
```

It is not a general BepInEx release. It is maintained for Romestead and keeps
only the runtime path this game needs.

It uses a local `d3d11.dll` hook and keeps the usual BepInEx folder layout,
logging, and HarmonyX plugin patching.

## Installation

Use the release package for your platform.

### Windows

1. Open Romestead's local files from Steam.
2. Extract the `win-x64` package into the game folder.
3. Confirm that `d3d11.dll` is next to `Romestead.exe`.

### Linux / Steam Proton

Romestead currently runs on Linux through Proton, not as a native Linux build.

1. Open Romestead's local files from Steam.
2. Extract the `linux-x64` package into the game folder.
3. Confirm that `d3d11.dll` is next to `Romestead.exe`.

Plugin DLLs go in:

```text
BepInEx/plugins
```

Logs are written to:

```text
BepInEx/LogOutput.log
```

## Building

Build the solution:

```powershell
dotnet build .\BepInEx.sln -c Release
```

Create a release package:

```powershell
.\packaging\package-release.ps1 -Configuration Release -Runtime win-x64
.\packaging\package-release.ps1 -Configuration Release -Runtime linux-x64
```

Packages are written to `artifacts/`.

## Notes

- If BepInEx stops loading after a game update, extract the package again.
- Older installs may still have a `STARTUP_HOOKS` entry in
  `Romestead.runtimeconfig.json`. The current client package does not need it.

## Credits

- BepInEx team and contributors
- Romestead-specific changes by ibox233 / Ice Box Studio
- HarmonyX, MonoMod, Mono.Cecil, and other dependency maintainers

This project is unofficial and is not affiliated with Romestead's developer or
publisher.

## License

BepInEx is licensed under LGPL-2.1. This fork keeps the upstream license and
copyright notices.

Third-party dependencies keep their own licenses. Do not redistribute Romestead
game binaries, game assets, Steam files, or user logs.

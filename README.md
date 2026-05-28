# BepInEx 6 CoreCLR for Romestead

This repository is a Romestead-specific, CoreCLR-only fork of BepInEx BE755.

It is based on upstream BepInEx commit:

```text
3fab71a1914132a1ce3a545caf3192da603f2258
```

This fork is not a full general-purpose BepInEx distribution. Unity Mono,
Unity IL2CPP, Doorstop, and .NET Framework launcher support have been removed.
The remaining loader targets Romestead's .NET 8 / MonoGame Windows build via
the CoreCLR startup hook path.

## What It Keeps

- BepInEx plugin metadata and chainloader model.
- `BepInEx/plugins`, `BepInEx/config`, `BepInEx/core`, and `BepInEx/patchers`
  layout.
- Console and file logging.
- CoreCLR startup hook entrypoint.
- HarmonyX-based runtime patching.

## Main Changes

- Targets CoreCLR at `net8.0`.
- Treats the Romestead game root as the managed assembly directory.
- Avoids Unity-style `*_Data/Managed` path detection.
- Makes the startup hook idempotent.
- Updates HarmonyX to `2.16.1`.
- Removes non-CoreCLR runtime projects from this fork.

## Build

```powershell
dotnet build .\BepInEx.sln -c Release
```

The CoreCLR output is produced under:

```text
bin/NET.CoreCLR/net8.0
```

## More Notes

See [ROMESTEAD_FORK.md](ROMESTEAD_FORK.md) for install notes and redistribution
guidance.

## License

BepInEx is licensed under LGPL-2.1. This fork preserves the upstream license and
copyright notices. Third-party dependencies keep their own licenses.

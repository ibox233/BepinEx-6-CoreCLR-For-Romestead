Romestead Server BepInEx Mod Loader

This package is the dedicated server variant of the Romestead-specific
BepInEx CoreCLR mod loader.

Install:

1. Stop the Romestead dedicated server.
2. Extract this archive directly into the Romestead dedicated server folder.
   After extraction, install.sh should be next to Server.runtimeconfig.json.
3. Run sh install.sh from the server folder.
4. Start the server normally.

What the installer changes:

- It edits Server.runtimeconfig.json.
- It adds STARTUP_HOOKS pointing to BepInEx.NET.CoreCLR.dll.
- It creates Server.runtimeconfig.json.bepinex-backup before the first change.
- It does not include or modify Romestead game/server files.

Plugins:

Place server plugin DLLs here:

  BepInEx/plugins

Logs:

  BepInEx/LogOutput.log

Uninstall:

Run sh uninstall.sh from the server folder. It restores the runtimeconfig backup
when available and removes the root loader files. The BepInEx folder is kept so
server plugins and configuration files are not deleted.

Important:

- This package targets Server.runtimeconfig.json, not Romestead.runtimeconfig.json.
- If Steam verifies server files or the server updates, the startup hook may be
  removed. Run sh install.sh again if BepInEx stops starting.
- This modified loader is experimental and has not been fully tested with every
  server workflow or future server update.

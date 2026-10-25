# Riverheim AtlasBuilder UI

A point-and-click window for [Gurebu's Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/): type a Valheim world seed, click **Generate map**, and get a picture of the whole Riverheim world. Windows only. A community tool, not made or endorsed by Gurebu.

- Maps are drawn by **the Riverheim you have installed**, so they match the worlds you play.
- Try **your own world settings** from [Riverheim Config](https://thunderstore.io/c/valheim/p/Wackah/Riverheim_Config/) and see the result before you create a world.

## How to use

1. Install this with your mod manager, in the same profile as **Riverheim** (AtlasBuilder comes with it).
2. Open the profile folder: in Thunderstore Mod Manager or r2modman, *Settings* → *Browse profile folder*, then `BepInEx` → `plugins` → `Wackah-Riverheim_AtlasBuilder_UI`.
3. Double-click **Run-AtlasBuilder-UI.cmd**.
4. Type your world seed and click **Generate map**. Maps are saved to `Pictures\Riverheim Maps`.

The first map takes about half a minute longer while the launcher gets your Riverheim ready; if your antivirus asks about AtlasBuilder or PowerShell, allow it.

**Custom world settings:** tick the box, then **Import config** to load your server's `com.valheim.riverheim.config.cfg`, or change fields yourself (**Find setting** searches them). **Export config** saves them for the game.

Full guide, troubleshooting and source: [github.com/lwackahg/atlasbuilder-ui-repo](https://github.com/lwackahg/atlasbuilder-ui-repo).

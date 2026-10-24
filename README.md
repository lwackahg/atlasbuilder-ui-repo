# Riverheim AtlasBuilder UI

A point-and-click launcher for [Gurebu's Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/),
so you can generate Riverheim map images without touching a command line.

Windows only. Five small text files, ~150 KB total.

## What this is and isn't

- It **is** a UI wrapper. It builds the command line for you, runs the tool, and keeps track of what settings made which map.
- It **does not** include `Riverheim.AtlasBuilder.exe`. That's Gurebu's tool — you install it from Thunderstore. This repo only ships the launcher.
- It is **not** affiliated with or endorsed by Gurebu. It's a community convenience wrapper.
- There is no installer, no binary download, and nothing that runs in the background. It's five plain-text files you can read in full before running:
  [`AtlasBuilder-Launcher.ps1`](AtlasBuilder-Launcher.ps1), [`Run-AtlasBuilder-UI.cmd`](Run-AtlasBuilder-UI.cmd), and, only used by the optional [custom world settings](#about-custom-world-settings), [`RiverheimConfigHook.cs`](RiverheimConfigHook.cs), [`RiverheimSettings.cs`](RiverheimSettings.cs) and [`settings.json`](settings.json). The last two are unmodified copies from the [Riverheim Config](https://github.com/lwackahg/Riverheim_Config) mod: its settings table and the field list exported from it.

## Install

1. Install [Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/) from Thunderstore if you haven't.
2. Download the five files from the [latest release](../../releases/latest) (or use **Code → Download ZIP**).
3. If you downloaded a zip: right-click it → **Properties** → tick **Unblock** → OK, *then* extract. Windows flags scripts that came from the internet, and this is how you clear it.
4. Drop all five files into the folder that already contains `Riverheim.AtlasBuilder.exe`.

   With Thunderstore Mod Manager that's usually:

   ```
   %AppData%\Thunderstore Mod Manager\DataFolder\Valheim\profiles\<YOUR PROFILE>\BepInEx\plugins\Gurebu-Riverheim_AtlasBuilder
   ```

   Paste that into the Explorer address bar and swap in your profile name. On r2modman it's the same but under `r2modmanPlus-local`.

5. Double-click **`Run-AtlasBuilder-UI.cmd`**.

## Usage

The **AtlasBuilder** path fills itself in automatically as long as the launcher is sitting next to the exe. If it isn't, hit **Browse** and point at it.

Enter your world seed, optionally a **Tag** (a short name like `more-lakes`), pick an output folder (defaults to `Pictures\Riverheim Maps`), choose your map modes, and hit **Generate map**. The large preview on the right shows the maps in your output folder, newest first — use **<** and **>** to step through them. The **Settings guide** button explains every option in the window.

### Batch runs with the queue

**Add to queue** saves everything currently set in the window as a job, so you can change settings (or the seed, tag, modes, world settings…) and add more. Type several seeds separated by commas (`400, 401, 69`) to add one job per seed. **Generate map** adds the current settings and runs the whole queue.

The **Queue** tab lists every job with its seed, tag, modes, size, settings code and status. **Run queue** starts the pending jobs, **Stop** finishes the map that is generating and then stops, **Remove** deletes the selected jobs, and **Clear finished** tidies up. If one job fails, the queue carries on with the next. Jobs you add while the queue is running are picked up automatically.

### Map file names

Maps are saved as `seed_mode_tag_settings_time`, for example:

```
400_Rich_more-lakes_custom-a1b2c3_20260914-213045.png
400_Rich_Default_20260914-212910.png
```

The settings part is the preset name, or `custom-` plus a short code that is identical whenever the world settings are identical — so two maps with the same code were made with the same settings. Runs never overwrite each other, so the same seed with different settings sits side by side.

### Presets

**Preset** picks which world AtlasBuilder generates; the line under it describes the selected one.

| Preset | What it generates |
| --- | --- |
| Default | Normal Riverheim world, 10.5 km radius. Matches a regular Riverheim world. |
| Experimental | Same world as Default, drawn with the newer Ashlands lava look. |
| Mini | Small 4 km world with its own simpler landmass layout. |
| MiniExp | The Mini world with the newer Ashlands lava look. |
| Token | Tiny 2 km world made of a single landmass. |
| HugeWorld | Huge 25 km world with the poles and landmass layout rescaled to fit. |

### Custom world settings, captions and history

**Custom world settings** lets you draw maps with your own world settings — world size and depths, rivers, lakes, biome bias, **biome amounts** (how much contested land each biome takes), **biome bands** (how far from spawn Meadows reaches and where Swamp, Plains and Mistlands appear), and since 3.0 of the mod also **landmass** shape, **mountains**, **river features**, **sub-biomes**, **terrain feel** and the **polar belts** — exactly the settings, with the same names and Riverheim 1.2.1 defaults, as the [Riverheim Config](https://github.com/lwackahg/Riverheim_Config) mod (the field list is read from the mod's `settings.json`, see [SETTINGS.md](https://github.com/lwackahg/Riverheim_Config/blob/main/SETTINGS.md) for the full reference). Every field starts at the Riverheim default and turns blue when changed; a field left at its default leaves Riverheim's own value alone. Hover the blue **?** next to a field for what it does. **Import config** fills the fields from a Riverheim Config mod file so maps match your server (and also reads `expand_world_size.cfg` from the same folder); **Reset** puts them back. **Export config** writes the fields out as a Riverheim Config mod file for your server or profile, backing up the old file first.

The lowland Black Forest settings (`ForestLowlandsWeight` and its shaping) only show with the **Installed** choice; the Riverheim bundled with AtlasBuilder 1.0.0 is too old to have them.

**Stamp seed and settings under each map** (on by default) adds a caption strip below each image with the seed, map mode, preset, tag and any changed world settings, so a shared map explains itself. The map itself isn't covered.

**Every generated image gets a matching `.riverheim.json` sidecar** saved next to it, recording the seed, tag and all settings used, including every world setting. **Map history** browses an output folder, previews thumbnails, filters by mode or grid, and can load any past map's settings straight back into the generator.

## About custom world settings

AtlasBuilder has no option for custom world values, so the launcher adds them the least invasive way .NET allows:

1. The first time you use them, the launcher builds [`RiverheimConfigHook.cs`](RiverheimConfigHook.cs) together with [`RiverheimSettings.cs`](RiverheimSettings.cs) into a small DLL using the C# compiler that is already part of Windows (.NET Framework 4), and stores it in `%LocalAppData%\RiverheimAtlasBuilderUI`. To compile against the right Riverheim version, it first starts AtlasBuilder once with no arguments so it unpacks itself into that same folder.
2. When you generate a map, the launcher writes your settings to a file in that folder and starts AtlasBuilder with a [.NET startup hook](https://github.com/dotnet/runtime/blob/main/docs/design/features/host-startup-hook.md) pointing at the DLL. Both are set only for AtlasBuilder.
3. The hook registers a Riverheim world preset — the same extension point Riverheim uses for its own Experimental preset — built from the normal Default world plus your settings. The launcher then asks AtlasBuilder for that preset.

`RiverheimSettings.cs` is the Riverheim Config mod's own settings table, compiled unchanged, so the launcher applies a setting exactly the way the mod does in game. The mod's test suite renders through this same hook to prove that stock values reproduce AtlasBuilder's Default preset byte for byte and that every setting changes the map.

Nothing is downloaded, nothing runs after AtlasBuilder closes, and no game, mod or AtlasBuilder files are modified. Leave **Custom world settings** unticked and the launcher runs AtlasBuilder exactly as before.

With the **Installed** choice the map is drawn by the same Riverheim your game runs, so it matches your world. With **Bundled** it comes from the older Riverheim inside AtlasBuilder 1.0.0 and can differ. See [Which Riverheim draws the map](#which-riverheim-draws-the-map).

## Which Riverheim draws the map

AtlasBuilder 1.0.0 bundles its own copy of Riverheim, and it is older than the mod: for the same seed, its maps differ from a world created in game with Riverheim 1.2 (coastlines, the Deep North and biome edges shift). The **Riverheim** choice under the AtlasBuilder path fixes that:

- **Installed (matches your game)** — the default when it can be found. The launcher draws with the `Riverheim.dll` from your own profile (`BepInEx\plugins\Gurebu-Riverheim`, right next to AtlasBuilder), so maps match your worlds. The text beside the choice shows the version it found.
- **Bundled (older, can differ)** — what AtlasBuilder shows on its own.

The first map with a new Riverheim version takes about half a minute longer: the launcher prepares a copy of AtlasBuilder's files in `%LocalAppData%\RiverheimAtlasBuilderUI\engines` with your `Riverheim.dll` swapped in (renamed to the name AtlasBuilder looks for) and AtlasBuilder's Default preset pointed at the version Riverheim gives new worlds, using the `Mono.Cecil.dll` that BepInEx already ships. It then draws a small test map to make sure everything works. After that, AtlasBuilder's own, unmodified exe runs on those files, with a small startup hook (built the same way as the custom settings hook) that finds the BepInEx and Unity files `Riverheim.dll` refers to in your profile's `BepInEx\core` and your Valheim install. When Riverheim updates, the launcher notices and prepares the new version by itself.

Nothing is downloaded, and no game, mod or AtlasBuilder file is changed: the only thing taken from your profile is a renamed copy of `Riverheim.dll` in that cache folder, and the BepInEx and Unity files are only read where they are. Every map records which Riverheim drew it, in its caption, its `.riverheim.json` sidecar and **Map history**.

If the launcher can't find something, the text beside the choice turns red and says what; click **Find...** and point at it. **Find...** also lets you pick the `Riverheim.dll` of a different profile. If preparing fails, the launcher says why and offers to draw with the bundled Riverheim instead.

### Bigger worlds: World radius vs Expand World Size

**World radius** changes how far Riverheim itself generates. Riverheim's biome bands are measured as a share of the world size, so they scale with it — but the Ashlands and Deep North poles, the landmass swirl and the rainfall pattern are fixed in metres (the HugeWorld preset rescales those by hand). A bigger radius therefore distorts the layout instead of just scaling it up.

For a bigger world with the normal layout, keep World radius at 10500 and use [Expand World Size](https://thunderstore.io/c/valheim/p/JereKuusela/Expand_World_Size/) **stretching**, which Riverheim supports. In the launcher's **World size** section at the bottom of the settings (the only place to set the world size, bigger or smaller), set **In-game radius** or **EWS stretch** — they're linked (stretch = radius ÷ 10500) — and click **Copy EWS settings** for the four lines to paste into `expand_world_size.cfg`. For a 13000 m world:

```ini
World radius = 12500
World edge size = 500
Stretch world = 1.2381
Stretch biomes = 1.2381
```

The launcher never edits that file. Stretching scales the whole normal world, so the map picture looks the same and the caption shows the in-game size. Per Riverheim's README, Stretch world and Stretch biomes must be equal, and EWS World radius + World edge size must equal 10500 × stretch. If World radius is also changed, the launcher offers to set it back to 10500 or move that size into EWS stretching; **Import config** warns about it too.

Two things to know about stretched worlds in game. Install [Riverheim Config](https://github.com/lwackahg/Riverheim_Config) 3.0 or newer: without it, trees, grass and many locations are missing beyond about 10 km, because Expand World Size does not stretch Riverheim's forest map. And Valheim's shaders draw snow on everything more than about 8,000 m north of the centre whatever the stretch, so the normal land between there and the Deep North looks snow-covered; that is only the look, and the map image is not affected.

## About the `-ExecutionPolicy Bypass`

Fair question if you looked at the `.cmd` and got twitchy about it:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AtlasBuilder-Launcher.ps1"
```

Windows blocks unsigned `.ps1` files by default, and code signing needs a certificate that costs real money. `Bypass` applies **only to this one launch of this one script** — it doesn't change any machine setting or persist after the window closes. `-STA` is required because the UI uses Windows Forms. `-NoProfile` means your PowerShell profile isn't loaded.

You should be skeptical of scripts from the internet. That's exactly why this is a readable text file in a public repo instead of an exe behind a Drive link — read it before you run it.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Window flashes and closes, or "running scripts is disabled" | You skipped the Unblock step. Right-click `AtlasBuilder-Launcher.ps1` → Properties → **Unblock**. |
| "Windows protected your PC" (SmartScreen) | **More info** → **Run anyway**. |
| "AtlasBuilder not found" | The launcher isn't next to the exe. Use **Browse** to point at `Riverheim.AtlasBuilder.exe`. |
| Nothing generates | Check the log pane at the bottom of the window — the exe's own output goes there. |
| Custom world settings are greyed out and say "Missing: ..." | `RiverheimConfigHook.cs`, `RiverheimSettings.cs` or `settings.json` isn't next to the launcher. Put all five files in the same folder. |
| Import config can't find the file | The Riverheim Config mod creates `BepInEx\config\com.valheim.riverheim.config.cfg` the first time the game starts with it installed. |
| "Could not prepare custom world settings" | The message includes the compiler output. Delete `%LocalAppData%\RiverheimAtlasBuilderUI` and try again; if it still fails, open an issue with that message. |
| AtlasBuilder window shows `[Custom world settings] Could not apply settings` | The map was drawn with stock settings. The same line says why. |
| A bigger World radius makes the map look distorted | Expected — see [Bigger worlds](#bigger-worlds-world-radius-vs-expand-world-size). |
| Maps don't match my world exactly | Check that **Riverheim** says *Installed* and shows the same version as your game, and that custom world settings (if any) match your server's config — **Import config** reads it. With *Bundled*, differences are expected. |
| "Riverheim mod not found" / "Valheim folder not found" in red | Click **Find...** next to it. Pick `Riverheim.dll` from your profile's `BepInEx\plugins\Gurebu-Riverheim`, or the folder that holds `valheim.exe` (in Steam: right-click Valheim → Manage → Browse local files). |
| The first map seems stuck at "Preparing Riverheim..." | Your antivirus may be asking whether to allow AtlasBuilder or PowerShell; allow it. Preparing happens once per Riverheim version. |
| "The launcher could not use your installed Riverheim" | The message says why. Choose **Yes** to draw with the bundled Riverheim for now. Deleting `%LocalAppData%\RiverheimAtlasBuilderUI\engines` makes the launcher prepare from scratch next time. |

## Requirements

Windows 10 or 11 with Windows PowerShell 5.1 (preinstalled — you don't need to install anything). Riverheim AtlasBuilder from Thunderstore. Custom world settings also use the C# compiler that comes with .NET Framework 4.8, which Windows 10 and 11 already include.

## License

MIT — see [LICENSE](LICENSE). Applies to the launcher only, not to AtlasBuilder itself.

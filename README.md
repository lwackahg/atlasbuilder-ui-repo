# Riverheim AtlasBuilder UI

A point-and-click window for [Gurebu's Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/): type a Valheim world seed, click **Generate map**, and get a picture of the whole Riverheim world. No command line.

- Maps are drawn by **the Riverheim you have installed**, so they match the worlds you play.
- Try **your own world settings** from the [Riverheim Config](https://github.com/lwackahg/Riverheim_Config) mod and see the result before you create a world.
- Windows only. A community tool, not made or endorsed by Gurebu.

## Quick start

### 1. Get the mods

In your mod manager (Thunderstore Mod Manager or r2modman), add **[Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/)** to the profile you play with. Have **[Riverheim](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim/)** in the same profile too, so maps match your game.

### 2. Download this launcher

1. On this page, click the green **Code** button → **Download ZIP**.
2. Right-click the downloaded zip → **Properties** → tick **Unblock** → **OK**. (Windows blocks scripts downloaded from the internet until you do this.)
3. Open your profile's AtlasBuilder folder. In the mod manager: *Settings* → *Browse profile folder*, then `BepInEx` → `plugins` → `Gurebu-Riverheim_AtlasBuilder`.
4. Copy everything from inside the zip's folder (the files and the `presets` folder) into it, next to `Riverheim.AtlasBuilder.exe`.

### 3. Open it

Double-click **`Run-AtlasBuilder-UI.cmd`** in that folder. Tip: right-click it → *Send to* → *Desktop (create shortcut)* so you can find it next time.

### 4. Make a map

1. Type your world seed in **World seed** (as shown in Valheim's world list).
2. Click **Generate map**.

The map appears on the right and is saved to `Pictures\Riverheim Maps`. The first map takes about half a minute longer while the launcher gets your installed Riverheim ready; if your antivirus asks about AtlasBuilder or PowerShell, allow it.

## Things you can do

| I want to… | Do this |
| --- | --- |
| See what my server's settings do | **Import config** → **Config file…** → pick the server's `com.valheim.riverheim.config.cfg` → **Generate map**. |
| Try settings before making a world | Tick **Custom world settings**, change fields (they turn blue), generate. **Find setting** searches by name, like `island` or `river`. Hover the blue **?** for what a field does. |
| Use those settings in game | **Export config** saves them as a Riverheim Config file for your profile or server (the old file is backed up). |
| Try a ready-made world | **Import config** → **Presets** (gentle themes like Pangaea, Archipelago, River Kingdom) or **Wild presets** (Great Rivers, Inland Sea, Atoll, The Alps…). Hover one for what it does. They are the [Riverheim Config presets](https://github.com/lwackahg/Riverheim_Config/tree/main/presets). |
| Compare several seeds | Type them separated by commas: `400, 401, 69`. |
| Compare map styles | **Choose…** next to Map modes: Rich (normal), Biomes, Landmass, RichTerrain, Hdr. |
| Make a bigger or smaller world | Set **In-game radius** at the bottom of the settings, then **Copy EWS settings** and paste them into Expand World Size's config. See [Bigger worlds](#bigger-worlds). |
| Find an old map and its settings | **Map history** lists every map with its settings and can load them back. |

Every map is saved with a caption (seed, style, changed settings, which Riverheim drew it) and a `.riverheim.json` file next to it that records everything used.

## The window, top to bottom

- **AtlasBuilder:** found automatically. Use **Browse** only if it says it can't be found.
- **Riverheim:** *Installed (matches your game)* draws with your profile's Riverheim; the text beside it says which version it found. *Bundled (older, can differ)* uses the older Riverheim inside AtlasBuilder 1.0.0. If something is red, click **Find…**.
- **World seed / Tag / World count:** the seed; an optional short name added to the file name (like `more-lakes`); `-1` draws exactly this seed, a number above 0 draws that many related seeds.
- **Output folder, Map modes, Resolution:** where maps go, which styles to draw, and image size (bigger is sharper and slower).
- **Preset:** AtlasBuilder's own worlds (Default, Mini, Token, HugeWorld…). Locked to Default while custom world settings are on.
- **Stamp seed and settings under each map:** the caption strip. Untick for clean images.
- **Custom world settings:** every Riverheim Config setting, with Riverheim's defaults. A field left at its default leaves Riverheim's own value alone.
- **Generate map / Add to queue:** run now, or collect several jobs and run them with **Run queue**. The **Log** tab shows what AtlasBuilder printed.
- **Settings guide:** explains every option inside the window.

## Bigger worlds

Keep **World radius** at 10500 and let [Expand World Size](https://thunderstore.io/c/valheim/p/JereKuusela/Expand_World_Size/) stretch the world instead: Riverheim's poles, swirl and rainfall are measured in metres, so a bigger radius distorts the layout rather than scaling it. Set **In-game radius** (or **EWS stretch**; they are linked) at the bottom of the settings and click **Copy EWS settings**. For a 13000 m world:

```ini
World radius = 12500
World edge size = 500
Stretch world = 1.2381
Stretch biomes = 1.2381
```

In game, install Riverheim Config 3.0 or newer too: without it, trees, grass and many locations are missing beyond about 10 km in stretched worlds. Valheim also draws snow on everything more than about 8 km north whatever the stretch; that is only the look.

Riverheim cannot generate a world with a **World radius** between 7800 and 9000 m, so the launcher refuses those.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| The window flashes and closes, or "running scripts is disabled" | The files are still blocked by Windows. Right-click `AtlasBuilder-Launcher.ps1` → **Properties** → **Unblock**. |
| "Windows protected your PC" | **More info** → **Run anyway**. |
| "AtlasBuilder not found" or "not the Windows version of AtlasBuilder" | Click **Browse** and pick `Riverheim.AtlasBuilder.exe` (with `.exe`), usually in `BepInEx\plugins\Gurebu-Riverheim_AtlasBuilder`. |
| "Riverheim mod not found" / "Valheim folder not found" in red | Click **Find…**: pick `Riverheim.dll` from your profile (`BepInEx\plugins\Gurebu-Riverheim`), or the folder that holds `valheim.exe` (Steam: right-click Valheim → Manage → Browse local files). |
| The first map seems stuck at "Preparing Riverheim…" | Your antivirus is probably asking about AtlasBuilder or PowerShell; allow it. This happens once per Riverheim version. |
| "The launcher could not use your installed Riverheim" | The message says why. **Yes** draws with the bundled Riverheim for now. Deleting `%LocalAppData%\RiverheimAtlasBuilderUI\engines` makes it start fresh next time. |
| Nothing generates | Open the **Log** tab at the bottom; AtlasBuilder's own messages are there. |
| Maps don't match my world | Check **Riverheim** says *Installed* with your game's version, and that custom settings match your server (**Import config**). With *Bundled*, differences are expected. |
| **Import config** can't find the file | The Riverheim Config mod creates `BepInEx\config\com.valheim.riverheim.config.cfg` the first time the game starts with it. |
| Custom world settings are greyed out ("Missing: …") | A launcher file is missing. Copy all the files from the downloaded zip into the same folder again. |

<details>
<summary><b>How it works</b> (for the curious)</summary>

**Custom world settings.** AtlasBuilder has no option for custom values, so the launcher compiles [`RiverheimConfigHook.cs`](RiverheimConfigHook.cs) together with [`RiverheimSettings.cs`](RiverheimSettings.cs) into a small DLL with the C# compiler built into Windows, and starts AtlasBuilder with it as a [.NET startup hook](https://github.com/dotnet/runtime/blob/main/docs/design/features/host-startup-hook.md). The hook registers a Riverheim world preset (the extension point Riverheim uses for its own Experimental preset) built from the Default world plus your settings. `RiverheimSettings.cs` and `settings.json` are unmodified copies from the Riverheim Config mod, so the launcher applies each setting exactly as the mod does in game.

**Installed Riverheim.** AtlasBuilder 1.0.0 bundles an older Riverheim than the mod, so for the same seed its maps differ from worlds made with Riverheim 1.2. The first time, the launcher copies AtlasBuilder's unpacked files to `%LocalAppData%\RiverheimAtlasBuilderUI\engines`, swaps in your `Riverheim.dll` (renamed to the name AtlasBuilder expects) and points AtlasBuilder's Default preset at the version Riverheim gives new worlds, using the `Mono.Cecil.dll` that BepInEx ships. It draws a small test map to check everything works. After that, AtlasBuilder's own unmodified exe runs on those files with a second small hook that finds the BepInEx and Unity files Riverheim refers to, in your profile and your Valheim install. When Riverheim updates, this happens again by itself.

Nothing is downloaded and no game, mod or AtlasBuilder file is changed. Everything the launcher makes lives in `%LocalAppData%\RiverheimAtlasBuilderUI`.

**Why the `.cmd` uses `-ExecutionPolicy Bypass`.** Windows blocks unsigned PowerShell scripts by default, and signing needs a paid certificate. `Bypass` applies only to this one launch of this one script and changes no setting. `-STA` is needed for the window, `-NoProfile` skips your PowerShell profile. Every file is plain text you can read before running it.

</details>

## Requirements

Windows 10 or 11 (PowerShell 5.1 and .NET Framework 4.8 are built in) and [Riverheim AtlasBuilder](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim_AtlasBuilder/). For maps that match your game: [Riverheim](https://thunderstore.io/c/valheim/p/Gurebu/Riverheim/) in the same profile.

## License

MIT, see [LICENSE](LICENSE). Covers the launcher only, not AtlasBuilder.

# CLAUDE.md — CreamInstaller Codebase Guide

## Project Overview

**CreamInstaller** is a Windows desktop application (WinForms, C#, .NET 8) that automatically finds installed Steam, Epic Games, and Ubisoft games and installs/configures DLC unlocker DLLs for them. It embeds third-party unlocker binaries (Koaloader, SmokeAPI, ScreamAPI, Uplay R1/R2 Unlocker) directly into the executable and extracts/installs them as needed.

- **Version:** 4.10.1
- **Target:** Windows 8+ (64-bit only)
- **Framework:** `net8.0-windows10.0.22621.0`
- **Output:** Single self-contained `.exe` (compressed, all DLLs embedded)

---

## Repository Structure

```
CreamInstaller/
├── CreamInstaller.sln                # Visual Studio solution
└── CreamInstaller/                   # Main project
    ├── CreamInstaller.csproj         # Project file, embedded resources, NuGet refs
    ├── Program.cs                    # Entry point, mutex, global exception handling
    ├── ProgramRelease.cs             # GitHub release model for auto-update
    ├── Selection.cs                  # Core model: a detected game (Platform enum + metadata)
    ├── SelectionDLC.cs               # Core model: a DLC belonging to a Selection
    ├── Components/                   # Reusable UI components
    │   ├── ContextMenuItem.cs        # Custom context menu item
    │   ├── CustomForm.cs             # Base form with helpers
    │   ├── CustomTreeView.cs         # Extended TreeView
    │   └── PlatformIdComparer.cs     # IComparer for sorting by platform+id
    ├── Forms/                        # WinForms UI (each has .cs + .Designer.cs + .resx)
    │   ├── UpdateForm.cs             # Startup/update check form
    │   ├── SelectForm.cs             # Main game+DLC selection UI
    │   ├── InstallForm.cs            # Install/uninstall progress UI
    │   ├── DialogForm.cs             # Generic dialog helper
    │   ├── SelectDialogForm.cs       # Selection dialog
    │   └── DebugForm.cs              # Debug log viewer (DEBUG builds only)
    ├── Platforms/                    # Platform-specific detection & API access
    │   ├── Steam/
    │   │   ├── SteamLibrary.cs       # Registry + ACF parsing to detect Steam games
    │   │   ├── SteamCMD.cs           # SteamCMD download, install, DLC querying
    │   │   ├── SteamStore.cs         # Steam Store API calls
    │   │   ├── ValveDataFile.cs      # VDF parser (uses Gameloop.Vdf)
    │   │   └── AppDetails.cs         # Steam app detail models
    │   ├── Epic/
    │   │   ├── EpicLibrary.cs        # Epic manifest detection
    │   │   ├── EpicStore.cs          # Epic GraphQL API calls
    │   │   ├── Manifest.cs           # Epic manifest model
    │   │   ├── GraphQL/              # GraphQL request/response models
    │   │   └── Heroic/               # Heroic Launcher support
    │   ├── Ubisoft/
    │   │   └── UbisoftLibrary.cs     # Ubisoft registry-based detection
    │   └── Paradox/
    │       └── ParadoxLauncher.cs    # Paradox Launcher repair logic
    ├── Resources/                    # Embedded DLL payloads + C# wrappers
    │   ├── Koaloader/                # 40+ proxy DLLs (audioses, d3d9/10/11, dinput8…) × 32/64-bit
    │   ├── SmokeAPI/                 # steam_api.dll + steam_api64.dll
    │   ├── ScreamAPI/                # EOSSDK Win32/Win64 Shipping DLLs
    │   ├── UplayR1/                  # uplay_r1_loader.dll + 64-bit
    │   ├── UplayR2/                  # upc_r2_loader.dll + 64-bit
    │   ├── Koaloader.cs              # Install/uninstall/configure Koaloader
    │   ├── SmokeAPI.cs               # Install/uninstall/configure SmokeAPI
    │   ├── ScreamAPI.cs              # Install/uninstall/configure ScreamAPI
    │   └── UplayR1.cs                # Install/uninstall/configure Uplay R1
    ├── Utility/                      # Cross-cutting helpers
    │   ├── SafeIO.cs                 # Extension methods for all file/dir I/O (retry loops)
    │   ├── ProgramData.cs            # App data dir, JSON choices persistence, cooldowns
    │   ├── HttpClientManager.cs      # Singleton HttpClient lifecycle
    │   ├── IconGrabber.cs            # Game icon extraction
    │   ├── NativeImports.cs          # P/Invoke signatures (e.g. BinaryType detection)
    │   ├── LogTextBox.cs             # Thread-safe log text box wrapper
    │   ├── Diagnostics.cs            # Structured logging helpers
    │   └── ExceptionHandler.cs       # HandleException / HandleFatalException
    └── Properties/
        ├── AssemblyInfo.cs
        └── Resources.Designer.cs     # Auto-generated resource accessor
```

---

## Building

**Requirements:** .NET 8 SDK, Windows 10+ build host (Windows SDK 22621).

```bash
# Debug build
dotnet build CreamInstaller.sln -c Debug -p:Platform=x64

# Release build (produces CreamInstaller.exe)
dotnet publish CreamInstaller/CreamInstaller.csproj -c Release -p:Platform=x64
```

- Release assembly name: `CreamInstaller.exe`
- Debug assembly name: `CreamInstaller-debug.exe`
- Output is a **single self-contained file** (`PublishSingleFile`, compressed, debug symbols embedded).

**There is no test suite.** This project has no automated tests; all verification is manual.

---

## Key Data Flows

### Application Startup
1. `Program.Main()` acquires a named `Mutex` (single-instance guard).
2. `HttpClientManager.Setup()` creates the shared `HttpClient`.
3. `UpdateForm` is shown — checks GitHub releases, offers auto-update via download+replace.
4. After update check, `SelectForm` opens.

### Game Detection (SelectForm)
1. Each platform library (`SteamLibrary`, `EpicLibrary`, `UbisoftLibrary`) scans registry / manifest folders to find installed games.
2. Detected games are materialised as `Selection` objects (stored in `Selection.All`, a `ConcurrentDictionary`).
3. DLCs are materialised as `SelectionDLC` objects (stored in `SelectionDLC.All`).
4. For Steam games, `SteamCMD` is downloaded if absent; DLC metadata is fetched and cached in `C:\ProgramData\CreamInstaller\appinfo\`.
5. For Epic games, the Epic GraphQL API is called.

### Install / Uninstall (InstallForm)
1. For each enabled `Selection`, the relevant resource class (`Koaloader`, `SmokeAPI`, `ScreamAPI`, `UplayR1`) is invoked.
2. Resource classes extract embedded DLL bytes via `Assembly.GetManifestResourceStream`, write them to the game's DLL directories, and write JSON config files.
3. `Koaloader` is the DLL-proxy injector; other unlockers are the actual payload loaded by Koaloader.

### Persistence
- `ProgramData` stores JSON files in `C:\ProgramData\CreamInstaller\`:
  - `choices.json` — which games were selected
  - `dlc.json` — which DLCs were selected
  - `proxies.json` — Koaloader proxy choices
  - `cooldown\*.txt` — rate-limit timestamps for API calls

---

## Core Abstractions

### `Platform` enum (`Selection.cs`)
```csharp
public enum Platform { None = 0, Paradox, Steam, Epic, Ubisoft }
```

### `Selection` (game)
- Keyed by `(Platform, Id)` — `Id` is the platform's app/game identifier string.
- Holds `RootDirectory`, `DllDirectories`, `ExecutableDirectories` (with `BinaryType`).
- `Enabled` mirrors the `TreeNode.Checked` state (UI-driven).
- `Koaloader` / `KoaloaderProxy` control whether Koaloader is used and which DLL name.
- `Selection.DefaultKoaloaderProxy = "version"`.
- Protected games list: `Program.ProtectedGames` (`["PAYDAY 2"]`), also blocks directories containing `\EasyAntiCheat` or `\BattlEye`.

### `SelectionDLC` (DLC entry)
- Has a `DLCType` enum: `Steam`, `SteamHidden`, `Epic`, `EpicEntitlement`.
- Points back to its parent `Selection`.

---

## Code Conventions

### Naming
| Construct | Convention | Example |
|-----------|-----------|---------|
| Classes / Methods / Properties | PascalCase | `SelectForm`, `GetOrCreate` |
| Local variables / parameters | camelCase | `rootDirectory`, `dlcId` |
| Constants | SCREAMING_SNAKE or PascalCase | `DefaultKoaloaderProxy`, `ProtectedGames` |
| Private fields | camelCase or `_camelCase` | varies by file |

### Patterns
- **Extension methods on `string` for all I/O** — never call `File.*` or `Directory.*` directly; use `SafeIO` extensions (`.DirectoryExists()`, `.ReadFile()`, `.WriteFile()`, etc.). These wrap retry loops and surface user-visible dialogs on failure.
- **`ConcurrentDictionary<T, byte>` as a concurrent set** — `Selection.All` and `SelectionDLC.All` use `byte` as the dummy value.
- **Singleton forms via `static Current`** — `SelectForm.Current`, `UpdateForm.Current`, `DebugForm.Current` hold the live instance.
- **`#if DEBUG` blocks** — `DebugForm` attachment, debug-only logging; never gate production logic behind these.
- **`goto retry`** — used in `Program.Main()` for recoverable startup exceptions; acceptable in this specific location.
- **`Program.Canceled`** — a global cancellation flag checked throughout long-running loops; set by the user or on fatal errors.

### Async
- Long-running operations use `async Task` and are awaited by form event handlers.
- `async void` is used in a few fire-and-forget form callbacks — acceptable for event handlers only.

### Null handling
- Nullable reference types are enabled (`<Nullable>` is implicitly on via `LangVersion=latest`).
- Use `is null` / `is not null` pattern matching, not `== null`.

---

## NuGet Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `Gameloop.Vdf` | 0.6.2 | Parse Steam `.acf` / VDF files |
| `Newtonsoft.Json` | 13.0.3 | Serialize/deserialize user choices and API responses |
| `System.ServiceModel.Primitives` | 6.0.0 | WCF base types (used for transport-level helpers) |

---

## Runtime Data Locations (Windows)

| Path | Contents |
|------|---------|
| `C:\ProgramData\CreamInstaller\` | Root app data directory |
| `...\appinfo\` | SteamCMD and cached game/DLC metadata |
| `...\appinfo\version.txt` | Minimum version marker; directory is wiped on upgrade |
| `...\cooldown\*.txt` | Per-identifier API rate-limit timestamps |
| `...\choices.json` | Saved game selections |
| `...\dlc.json` | Saved DLC selections |
| `...\proxies.json` | Saved Koaloader proxy choices |

---

## GitHub / Release Workflow

- **Repository owner:** `pointfeev`, **repo:** `CreamInstaller`
- **Version scheme:** Semantic versioning (e.g. `4.10.1`), set in `<Version>` in the `.csproj`.
- Auto-update: on startup, `UpdateForm` queries the GitHub Releases API, downloads `CreamInstaller.zip`, replaces the running executable, and restarts.
- Branch for this documentation PR: `claude/add-claude-documentation-y78OP`

---

## Important Constraints for AI Assistants

1. **Windows-only project.** Do not suggest cross-platform changes; WinForms, P/Invoke, and Windows registry access are intentional.
2. **x64 only.** `<PlatformTarget>x64</PlatformTarget>` is intentional; do not add AnyCPU targets.
3. **No test suite.** Do not generate test project scaffolding unless explicitly asked.
4. **Embedded DLLs are binary resources.** Never modify `.csproj` `<EmbeddedResource>` entries without understanding that removing one will break the corresponding install path at runtime.
5. **SafeIO extensions are mandatory for file I/O.** Do not call `File.*` / `Directory.*` directly; always use the `SafeIO` extension methods so retry logic and user dialogs are preserved.
6. **Do not add logging frameworks.** The project uses `Diagnostics.cs` and `LogTextBox` for structured logging; keep this consistent.
7. **`Program.Canceled` must be respected.** All loops over game directories or API calls must check `Program.Canceled` and exit early.
8. **Single-instance guard is intentional.** The `Mutex` in `Program.Main()` prevents multiple instances; do not remove it.
9. **Code style enforcement is on.** `<EnforceCodeStyleInBuild>True</EnforceCodeStyleInBuild>` means style violations are build errors. Follow existing patterns.
10. **`LangVersion=latest`** — C# 12+ features (primary constructors, collection expressions, etc.) are available but should be used consistently with existing style.

# NordVPN Windows — built-in CLI reference (app 8.4.3.0)

The NordVPN Windows client has a built-in command-line interface, parsed with
`CommandLineParser` inside `NordVPNApp.dll`. This list was extracted directly
from the binary's `[Verb]` / `[Option]` / `[Value]` attributes (see
`spike/Inspect`), so it is the **complete** declared surface.

## How to invoke

```
"C:\Program Files\NordVPN\NordVPN.exe" <flags>
```

- **Syntax is flag-style: `--connect` / `--disconnect`** — *not* bare words like
  `connect`. (Short forms: `-c`, `-d`, etc.)
- It controls the **already-running** app (verified) and is **fire-and-forget**:
  `NordVPN.exe` is a GUI-subsystem binary, so it returns immediately and prints
  nothing to the console. Confirm results by observing state (this tool does).
- `NordVPN.exe` (the launcher) forwards to the running app; the versioned
  `…\8.4.3.0\NordVPNApp.exe` accepts the same flags directly.

---

## Connection — root options (`NordVpn.Launch.StartupArguments.StartupArgs`)

| Flag (short, long) | Type | Notes | Verified |
|---|---|---|---|
| `-c, --connect` | bool | Quick-connect to the best server. Combine with one of the target flags below. | ✅ |
| `-d, --disconnect` | bool | Disconnect from VPN. | ✅ |
| `-v, --version` | string | Show app version. | declared |
| `-g, --group-name` | string | Connect to best server in a country/group, e.g. `"Japan"`, `"United States"`, or a specialty group. | ✅ (Singapore confirmed) |
| `-n, --server-name` | string | Connect to a specific server by name, e.g. `"United States #5"`. | declared |
| `-i, --server-id` | string | Connect to a specific server by numeric id. | declared |
| `-r, --recent-name` | string | Connect to a recent/named entry. | declared |

> The target flags (`-g/-n/-i/-r`) are marked **hidden** in the binary but are
> documented in `--connect`'s own help text and are used as arguments to it.
> There is **no `--protocol` and no `--city` flag** — `--connect` uses whichever
> protocol the app is configured for (Automatic → NordLynx), and location
> granularity is country/group, specific server, or id.

### Examples (verified working on the running app)

```powershell
$nv = "C:\Program Files\NordVPN\NordVPN.exe"
& $nv --connect                              # quick connect (best)
& $nv --connect --group-name "Japan"         # change location -> Japan
& $nv --connect --server-name "United States #5"
& $nv --connect --server-id 12345
& $nv --disconnect
# reconnect = --disconnect then --connect [target]
```

---

## Meshnet — `meshnet` verb (`NordVpn.Launch.StartupArguments.MeshnetArgs`)

Invoked as a sub-verb: `NordVPN.exe meshnet <options>`.

| Option | Type | Help |
|---|---|---|
| `--send` | list | "File or folder to be sent. optionally prefixed with `<nord-name>`" (NordDrop file transfer) |
| `--more-devices` | bool | "Show all devices" |

*(Declared in the binary; not tested here.)*

---

## Internal / hidden launch flags (the app passes these to itself)

These exist on `StartupArgs` but are for the app's own launch scenarios, not
day-to-day control. Listed for completeness; default `False` unless noted.

| Flag | Likely purpose |
|---|---|
| `--rr` | reconnect-required / restart-and-reconnect |
| `--scheduled-start` | launched by a scheduled task |
| `--auto-start` | launched at login / auto-start |
| `--jumplist-attempt` | invoked from the Windows taskbar jump-list |
| `--started-from-update` (`-s`) | relaunched after an update |
| `--skip-onboarding` | skip first-run onboarding |
| `--accept-data-consent` | pre-accept data consent |
| `--skip-tp-info-popup` | skip the Threat Protection info popup |

---

## What is NOT in the CLI

- No `--status` / `--list` style read commands — the CLI only **triggers**
  actions; it returns nothing on stdout. Read state another way (this tool reads
  the active tunnel + a through-tunnel exit check).
- No `--protocol`, no `--city`, no login/logout, no settings toggles. Those live
  only in the GUI or behind the (auth-gated) gRPC service API.

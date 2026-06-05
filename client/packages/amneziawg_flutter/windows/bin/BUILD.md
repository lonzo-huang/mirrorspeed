# Windows AWG runtime binaries

The Windows build bundles these two files next to `mirrorspeed_vpn.exe`
(via the `amneziawg_flutter_bundled_libraries` convention in `../CMakeLists.txt`):

| File                | Source                                                        |
|---------------------|---------------------------------------------------------------|
| `amneziawg_svc.exe` | Built from `amnezia-vpn/amneziawg-windows` (see below)        |
| `wintun.dll`        | Official signed build, fetched by amneziawg-windows `build.cmd` (`wintun-0.14.1`, amd64) |

AmneziaWG runs in **userspace** (`amneziawg-go`) over WinTun, so `tunnel.dll`
and a WireGuard-NT driver (`wireguard.dll`) are **not** needed on Windows.

## How `amneziawg_svc.exe` was built

`amneziawg_svc.exe` is the same `amneziawg-windows` module built as a normal
executable instead of `tunnel.dll`. The upstream `main` is an empty stub (the
module is meant to be built `-buildmode c-shared`); we add a real `main` that
reads the `.conf` path argv and calls the service entry point `Run()`.

Two Windows-service gotchas are handled in `main`:

1. **Invalid std handles.** A service has no console, so fd 0/1/2 are invalid;
   stock Go's runtime writing to the invalid stderr aborts the process with
   "The handle is invalid" (ERROR_INVALID_HANDLE) *before the tunnel starts*.
   (WireGuard avoids this with a patched Go; amneziawg-windows uses stock Go.)
   We redirect the std handles to a log file so those writes succeed.
2. **Unreadable logs.** `InitGlobalLogger` redirects the `log` package to a
   binary ring buffer (`log.bin`). We dump that ring buffer to the plain-text
   `amneziawg_svc.log` (next to the conf) on exit, so failures are diagnosable.

```go
// main.go — replace `func main() {}` with main() + redirectStdHandles() that:
//   - os.OpenFile(<confdir>/amneziawg_svc.log), SetStdHandle(STDOUT/STDERR),
//     os.Stdout/os.Stderr = f, log.SetOutput(f)
//   - read conf path argv, UseFixedGUIDInsteadOfDeterministic = true,
//     Run(string(data), name)
//   - defer: ringlogger.Global.WriteTo(logFile)
// imports add: os, path/filepath, strings, ringlogger
// (see git history of this dir / the amneziawg-windows fork for the full file)
```

> **Plugin requirement:** the service must be created with a **service SID**
> (`ChangeServiceConfig2(SERVICE_CONFIG_SERVICE_SID_INFO,
> SERVICE_SID_TYPE_UNRESTRICTED)`), otherwise AmneziaWG's WFP firewall step
> fails with "The specified group does not exist." See
> `../amneziawg_flutter_plugin.cpp` `InstallAndStartService`.

Build steps (Windows):

```bat
git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-windows
cd amneziawg-windows
:: edit main.go as above
build.cmd                            :: fetches Go + llvm-mingw + wintun, builds tunnel.dll

:: then build the service exe with the same toolchain (main.go imports "C" → CGO):
set PATH=%CD%\.deps\llvm-mingw\bin;%CD%\.deps\go\bin;%PATH%
set GOROOT=%CD%\.deps\go& set GOPATH=%CD%\.deps\gopath
set GOOS=windows& set GOARCH=amd64& set CGO_ENABLED=1& set CC=x86_64-w64-mingw32-gcc
go build -ldflags="-w -s" -trimpath -o amneziawg_svc.exe .
```

Then copy `amneziawg_svc.exe` and `.deps\wintun\bin\amd64\wintun.dll` here.

The plugin (`../amneziawg_flutter_plugin.cpp`, `GetSvcExePath`) looks for
`amneziawg_svc.exe` next to the app exe and registers it as a Windows service
with the generated `.conf` path as its argument.

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
reads the `.conf` path argv and calls the service entry point `Run()`:

```go
// main.go — replace `func main() {}` with:
func main() {
	if len(os.Args) < 2 {
		log.Fatalf("usage: %s <path-to.conf>", filepath.Base(os.Args[0]))
	}
	confPath := os.Args[1]
	data, err := os.ReadFile(confPath)
	if err != nil {
		log.Fatalf("read conf %q: %v", confPath, err)
	}
	name := strings.TrimSuffix(filepath.Base(confPath), ".conf")
	if err := Run(string(data), name); err != nil {
		log.Fatalf("service run: %v", err)
	}
}
// (add "os", "path/filepath", "strings" to imports)
```

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

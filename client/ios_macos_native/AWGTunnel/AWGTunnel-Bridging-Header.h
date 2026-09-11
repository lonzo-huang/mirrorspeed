// AWGTunnel 扩展的 bridging header：把 vendored WireGuardKit 需要的 C 符号引入 Swift。
//   - WireGuardKitC：x25519 / key 编解码（C 源码直接编进本 target）
//   - wireguard.h：amneziawg-go 导出的 wgTurnOn/wgTurnOff/…（WireGuardKitGo.xcframework）
#include "WireGuardKitC/WireGuardKitC.h"
#include "../wggo/wireguard.h"

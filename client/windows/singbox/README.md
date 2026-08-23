# Windows 免费节点引擎二进制（sing-box）

`SingboxWindowsRunner`（`lib/vpn/singbox_windows_runner.dart`）在 Windows 上以
子进程方式运行官方 `sing-box.exe`，用 wintun 建 tun 网卡。这两个二进制**不入库**，
需手动放到本目录，构建时 `windows/CMakeLists.txt` 会把它们复制到应用 exe 同目录。

## 放入以下两个文件

1. **sing-box.exe** — Windows amd64
   - https://github.com/SagerNet/sing-box/releases
   - 下载 `sing-box-<ver>-windows-amd64.zip`，解压取出 `sing-box.exe`
   - 与客户端 libbox 版本保持一致（当前 Android 侧为 1.13.x）

2. **wintun.dll** — amd64
   - https://www.wintun.net/  → `wintun-<ver>.zip` → `bin/amd64/wintun.dll`

放好后目录结构：
```
windows/singbox/
  ├─ README.md      (本文件)
  ├─ sing-box.exe
  └─ wintun.dll
```

## 运行时注意

- 创建 tun 网卡需**管理员权限**。首次运行请右键“以管理员身份运行”，
  或在安装包/快捷方式里请求管理员权限。
- `SingboxWindowsRunner` 用 `Process.start(exe, ['run','-c',cfg,'-D',<支持目录>])` 启动；
  config 由 `SingboxConfig.build()` 生成（与 Android 共用，`include_package` 已限定
  仅 Android 注入，桌面不会带该字段）。

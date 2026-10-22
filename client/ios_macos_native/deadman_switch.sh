#!/bin/bash
# 死人开关：到点无条件断开 MirrorSpeed 隧道，用于**远程**测试 macOS 版。
#
# 为什么需要：远程登录这台 Mac 做测试时，万一隧道把网络搞不通，远程会话一断就再也
# 连不回来。所以默认行为必须是「恢复网络」而不是「保持连接」——armed 之后你什么都
# 不做，到点它自己断开；只有你确认一切正常才手动 disarm。
#
# 为什么用 launchd 而不是 App 内看门狗：App/扩展本身出故障时，写在里面的看门狗也
# 跟着失效。这个开关跑在 App 之外，由系统的 launchd 驱动，App 崩了照样执行。
#
# 只停 provider 为 com.mirrorspeed.mirrorspeedVpn 的服务，不碰机器上其它 VPN。
# 不需要 sudo（NE 配置属当前用户）。
#
# 用法：
#   bash deadman_switch.sh arm [分钟]   # 默认 10 分钟
#   bash deadman_switch.sh status
#   bash deadman_switch.sh disarm       # 确认网络正常后执行
set -euo pipefail

PROVIDER="com.mirrorspeed.mirrorspeedVpn"
LABEL="com.mirrorspeed.deadman"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE="$HOME/.mirrorspeed-deadman.state"
LOG="$HOME/Library/Logs/mirrorspeed-deadman.log"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# 本机属于 MirrorSpeed 的 VPN 服务 UUID（可能有多条残留配置）
our_services() {
  scutil --nc list 2>/dev/null | awk -v p="$PROVIDER" '$0 ~ p {print $3}'
}

cmd_arm() {
  local mins="${1:-10}"
  [[ "$mins" =~ ^[0-9]+$ ]] && (( mins > 0 )) || { echo "❌ 分钟数必须是正整数"; exit 1; }

  local ids; ids="$(our_services || true)"
  [[ -n "$ids" ]] || echo "⚠️  当前没找到 MirrorSpeed 的 VPN 配置（App 还没创建过？）—— 开关照样装上，到点会重新查一次"

  mkdir -p "$(dirname "$PLIST")"
  # StartInterval 从加载时刻开始计时，首次触发即 N 分钟后；触发脚本会自行卸载，
  # 所以不会变成每 N 分钟循环执行。机器睡眠期间错过的触发会在唤醒后补执行（正是我们要的）。
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SELF</string>
    <string>fire</string>
  </array>
  <key>StartInterval</key><integer>$(( mins * 60 ))</integer>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF

  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null \
    || launchctl load -w "$PLIST"

  date +%s > "$STATE"
  echo "$mins" >> "$STATE"
  log "ARM: ${mins} 分钟后自动断开 MirrorSpeed 隧道"
  echo
  echo "✅ 已装好。$(date -v+${mins}M '+%H:%M:%S') 自动断开。"
  echo "   网络正常后记得执行：bash $(basename "$0") disarm"
}

cmd_disarm() {
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST" "$STATE"
  log "DISARM: 开关已撤除"
  echo "✅ 已撤除，不会再自动断开。"
}

cmd_status() {
  if [[ ! -f "$STATE" ]]; then
    echo "未装（armed=no）"
  else
    local at mins left
    at="$(sed -n 1p "$STATE")"; mins="$(sed -n 2p "$STATE")"
    left=$(( at + mins * 60 - $(date +%s) ))
    if (( left > 0 )); then
      echo "已装（armed=yes）：还有 $(( left / 60 )) 分 $(( left % 60 )) 秒自动断开"
    else
      echo "已装（armed=yes）：已过触发时刻（若机器睡过，唤醒后会补执行）"
    fi
  fi
  echo
  echo "MirrorSpeed 的 VPN 服务："
  scutil --nc list 2>/dev/null | grep -F "$PROVIDER" || echo "  （无）"
}

cmd_fire() {
  log "FIRE: 到点，开始断开"
  local ids; ids="$(our_services || true)"
  if [[ -z "$ids" ]]; then
    log "FIRE: 没找到 MirrorSpeed 的 VPN 服务，无需操作"
  else
    for id in $ids; do
      scutil --nc stop "$id" 2>&1 | tee -a "$LOG" || true
      log "FIRE: 已停 $id"
    done
  fi
  # 隧道由 App 发起，App 还在跑就可能被用户或自动逻辑重新连上 —— 一并退出它，
  # 确保「到点之后网络一定是通的」这个承诺成立。
  if pgrep -f "mirrorspeed_vpn" >/dev/null 2>&1; then
    pkill -f "mirrorspeed_vpn" 2>/dev/null || true
    log "FIRE: 已退出 App"
  fi
  # 一次性：触发后自行撤除，避免变成周期任务。
  # 注意顺序：bootout 会终止本任务（即自己），所以必须最后一步，
  # 否则后面的 rm/log 执行不到（实测状态文件会残留）。
  rm -f "$PLIST" "$STATE"
  log "FIRE: 完成，开关已自行撤除"
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
}

case "${1:-}" in
  arm)    shift; cmd_arm "${1:-10}" ;;
  disarm) cmd_disarm ;;
  status) cmd_status ;;
  fire)   cmd_fire ;;
  *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

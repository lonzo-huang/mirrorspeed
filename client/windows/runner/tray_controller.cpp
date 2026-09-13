#include "tray_controller.h"

#include <shellapi.h>

#include <flutter/standard_method_codec.h>

namespace {

// 菜单命令 id。固定项用独立 id，节点项用基址 + 下标。
constexpr UINT kCmdAuto = 1100;
constexpr UINT kCmdDisconnect = 1101;
constexpr UINT kCmdLaunch = 1102;
constexpr UINT kCmdShow = 1103;
constexpr UINT kCmdQuit = 1104;
constexpr UINT kCmdServerBase = 1200;  // 1200..1299（优质节点，按下标）
constexpr UINT kCmdFreeBase = 1300;    // 1300..1399（免费节点，按下标）

const wchar_t* kRunKey =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const wchar_t* kRunValue = L"MirrorSpeed";

// UTF-8（EncodableValue 的 std::string）→ UTF-16。
std::wstring U16(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                              static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      &w[0], n);
  return w;
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& m,
                                    const char* key) {
  auto it = m.find(flutter::EncodableValue(std::string(key)));
  return it == m.end() ? nullptr : &it->second;
}

std::string GetStr(const flutter::EncodableMap& m, const char* k) {
  if (const auto* v = Find(m, k)) {
    if (const auto* p = std::get_if<std::string>(v)) return *p;
  }
  return "";
}

bool GetBool(const flutter::EncodableMap& m, const char* k, bool dflt) {
  if (const auto* v = Find(m, k)) {
    if (const auto* p = std::get_if<bool>(v)) return *p;
  }
  return dflt;
}

int GetInt(const flutter::EncodableMap& m, const char* k, int dflt) {
  if (const auto* v = Find(m, k)) {
    if (const auto* p = std::get_if<int32_t>(v)) return *p;
    if (const auto* p = std::get_if<int64_t>(v)) return static_cast<int>(*p);
  }
  return dflt;
}

}  // namespace

TrayController::TrayController(flutter::BinaryMessenger* messenger, HWND hwnd)
    : hwnd_(hwnd) {
  zh_ = PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mirrorspeed/tray",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "update") {
          if (const auto* args =
                  std::get_if<flutter::EncodableMap>(call.arguments())) {
            OnUpdate(*args);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

TrayController::~TrayController() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void TrayController::OnUpdate(const flutter::EncodableMap& args) {
  status_ = GetStr(args, "status");
  if (status_.empty()) status_ = "disconnected";
  kind_ = GetStr(args, "kind");
  if (kind_.empty()) kind_ = "none";
  active_id_ = GetStr(args, "activeId");
  active_name_ = U16(GetStr(args, "activeName"));
  auto_select_ = GetBool(args, "autoSelect", true);
  quota_exceeded_ = GetBool(args, "quotaExceeded", false);
  elapsed_ = U16(GetStr(args, "elapsed"));
  speed_ = U16(GetStr(args, "speed"));
  trial_remaining_ = U16(GetStr(args, "trialRemaining"));

  // 从 servers/freeNodes 列表解析节点项（with_flag：优质节点带国旗前缀）。
  auto parse = [](const flutter::EncodableValue* v,
                  bool with_flag) -> std::vector<NodeItem> {
    std::vector<NodeItem> out;
    if (!v) return out;
    const auto* list = std::get_if<flutter::EncodableList>(v);
    if (!list) return out;
    for (const auto& e : *list) {
      const auto* m = std::get_if<flutter::EncodableMap>(&e);
      if (!m) continue;
      std::string id = GetStr(*m, "id");
      std::string name = GetStr(*m, "name");
      std::string flag = with_flag ? GetStr(*m, "flag") : "";
      int lat = GetInt(*m, "latency", -1);
      std::wstring label =
          U16((with_flag && !flag.empty()) ? (flag + " " + name) : name);
      if (lat >= 0) label += L"  " + std::to_wstring(lat) + L"ms";
      out.push_back({id, label});
    }
    return out;
  };

  servers_ = parse(Find(args, "servers"), /*with_flag=*/true);
  free_nodes_ = parse(Find(args, "freeNodes"), /*with_flag=*/false);

  UpdateTooltip();
}

void TrayController::UpdateTooltip() {
  NOTIFYICONDATAW nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd_;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_TIP;
  std::wstring tip = L"MirrorSpeed";
  if (!active_name_.empty() && status_ == "connected") {
    tip += L" · " + active_name_;
  }
  wcsncpy_s(nid.szTip, tip.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

void TrayController::ShowMenu() {
  auto tr = [this](const wchar_t* c, const wchar_t* e) -> const wchar_t* {
    return zh_ ? c : e;
  };

  HMENU menu = CreatePopupMenu();

  // 状态行（不可点）
  std::wstring st;
  if (status_ == "connected") {
    st = tr(L"已连接", L"Connected");
    if (!active_name_.empty()) st += L" · " + active_name_;
  } else if (status_ == "connecting") {
    st = tr(L"连接中…", L"Connecting…");
  } else if (status_ == "disconnecting") {
    st = tr(L"断开中…", L"Disconnecting…");
  } else {
    st = tr(L"未连接", L"Not connected");
  }
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, st.c_str());

  // 用量信息行（不可点）
  if (status_ == "connected" && !elapsed_.empty()) {
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0,
                (std::wstring(tr(L"已连接 ", L"Uptime ")) + elapsed_).c_str());
  }
  if (status_ == "connected" && !speed_.empty()) {
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, speed_.c_str());
  }
  if (!trial_remaining_.empty()) {
    std::wstring t =
        quota_exceeded_
            ? std::wstring(tr(L"免费时长已用完", L"Free time used up"))
            : std::wstring(tr(L"今日剩余 ", L"Remaining today ")) +
                  trial_remaining_;
    AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, t.c_str());
  }
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);

  // 优质节点（二级菜单：智能选择 + 各节点）
  HMENU pm = CreatePopupMenu();
  {
    bool on = kind_ == "premium" && auto_select_ && status_ == "connected";
    AppendMenuW(pm, MF_STRING | (on ? MF_CHECKED : MF_UNCHECKED), kCmdAuto,
                tr(L"智能选择", L"Auto select"));
    AppendMenuW(pm, MF_SEPARATOR, 0, nullptr);
    if (servers_.empty()) {
      AppendMenuW(pm, MF_STRING | MF_GRAYED, 0,
                  tr(L"暂无节点（请先登录）", L"No nodes — sign in first"));
    } else {
      for (size_t i = 0; i < servers_.size(); ++i) {
        bool sel = kind_ == "premium" && !auto_select_ &&
                   servers_[i].id == active_id_;
        AppendMenuW(pm, MF_STRING | (sel ? MF_CHECKED : MF_UNCHECKED),
                    kCmdServerBase + static_cast<UINT>(i),
                    servers_[i].label.c_str());
      }
    }
  }
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(pm),
              tr(L"优质节点", L"Premium nodes"));

  // 免费节点（二级菜单，只放延迟最低的若干个；完整列表在主窗口）
  HMENU fm = CreatePopupMenu();
  {
    if (free_nodes_.empty()) {
      AppendMenuW(fm, MF_STRING | MF_GRAYED, 0,
                  tr(L"测速中或暂无可用节点", L"Testing or none available"));
    } else {
      for (size_t i = 0; i < free_nodes_.size(); ++i) {
        bool sel = kind_ == "free" && free_nodes_[i].id == active_id_;
        AppendMenuW(fm, MF_STRING | (sel ? MF_CHECKED : MF_UNCHECKED),
                    kCmdFreeBase + static_cast<UINT>(i),
                    free_nodes_[i].label.c_str());
      }
      AppendMenuW(fm, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(fm, MF_STRING, kCmdShow, tr(L"更多节点…", L"More nodes…"));
    }
  }
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(fm),
              tr(L"免费节点", L"Free nodes"));

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  if (status_ == "connected" || status_ == "connecting") {
    AppendMenuW(menu, MF_STRING, kCmdDisconnect,
                tr(L"断开连接", L"Disconnect"));
  }
  AppendMenuW(menu,
              MF_STRING | (LaunchAtLoginEnabled() ? MF_CHECKED : MF_UNCHECKED),
              kCmdLaunch, tr(L"开机自启动", L"Launch at login"));
  AppendMenuW(menu, MF_STRING, kCmdShow, tr(L"打开主窗口", L"Open MirrorSpeed"));
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kCmdQuit, tr(L"退出", L"Quit"));

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd_);  // 点击别处时菜单能正确消失
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd_, nullptr);
  DestroyMenu(menu);  // 连同子菜单一并销毁
}

bool TrayController::HandleCommand(UINT id, bool* want_restore,
                                   bool* want_quit) {
  if (id == kCmdAuto) {
    Invoke("connect", "auto");
    return true;
  }
  if (id == kCmdDisconnect) {
    Invoke("disconnect", "");
    return true;
  }
  if (id == kCmdLaunch) {
    ToggleLaunchAtLogin();
    return true;
  }
  if (id == kCmdShow) {
    *want_restore = true;
    InvokeShow();
    return true;
  }
  if (id == kCmdQuit) {
    *want_quit = true;
    return true;
  }
  if (id >= kCmdServerBase &&
      id < kCmdServerBase + static_cast<UINT>(servers_.size())) {
    Invoke("connect", servers_[id - kCmdServerBase].id);
    return true;
  }
  if (id >= kCmdFreeBase &&
      id < kCmdFreeBase + static_cast<UINT>(free_nodes_.size())) {
    Invoke("connectFree", free_nodes_[id - kCmdFreeBase].id);
    return true;
  }
  return false;
}

void TrayController::InvokeShow() {
  if (channel_) channel_->InvokeMethod("show", nullptr);
}

void TrayController::Invoke(const char* method, const std::string& id) {
  if (!channel_) return;
  std::unique_ptr<flutter::EncodableValue> args;
  if (!id.empty()) {
    args = std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(id)}});
  }
  channel_->InvokeMethod(method, std::move(args));
}

bool TrayController::LaunchAtLoginEnabled() const {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  LONG r = RegQueryValueExW(key, kRunValue, nullptr, &type, nullptr, nullptr);
  RegCloseKey(key);
  return r == ERROR_SUCCESS && type == REG_SZ;
}

void TrayController::ToggleLaunchAtLogin() {
  bool on = LaunchAtLoginEnabled();
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return;
  }
  if (on) {
    RegDeleteValueW(key, kRunValue);
  } else {
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring quoted = L"\"";
    quoted += path;
    quoted += L"\"";
    RegSetValueExW(key, kRunValue, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(quoted.c_str()),
                   static_cast<DWORD>((quoted.size() + 1) * sizeof(wchar_t)));
  }
  RegCloseKey(key);
}

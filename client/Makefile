# MirrorSpeed VPN — 快捷构建命令
# 用法：make run-android  /  make build-apk  /  make build-ios  等

SUPABASE_URL   = https://yqckjzfwibklwokialac.supabase.co
SUPABASE_ANON  = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxY2tqemZ3aWJrbHdva2lhbGFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxOTY1MzcsImV4cCI6MjA5NDc3MjUzN30.NDxrGI6mgVMjgJvBchTkOCcT_ldiEEWtpJkFOhFGYNA
API_BASE       = https://mirrorspeed-portal.vercel.app

DEFINES = \
	--dart-define=SUPABASE_URL=$(SUPABASE_URL) \
	--dart-define=SUPABASE_ANON_KEY=$(SUPABASE_ANON) \
	--dart-define=API_BASE=$(API_BASE)

# ── 开发调试 ──────────────────────────────────────────────────
run-android:
	flutter run -d android $(DEFINES)

run-ios:
	flutter run -d ios $(DEFINES)

run-windows:
	flutter run -d windows $(DEFINES)

# ── 正式构建 ──────────────────────────────────────────────────
build-apk:
	flutter build apk --release $(DEFINES)
	@echo "\n✅ APK: build/app/outputs/flutter-apk/app-release.apk"

build-aab:
	flutter build appbundle --release $(DEFINES)
	@echo "\n✅ AAB: build/app/outputs/bundle/release/app-release.aab"

build-ios:
	flutter build ios --release $(DEFINES)
	@echo "\n✅ iOS archive ready — open Xcode to distribute"

build-ipa:
	flutter build ipa --release $(DEFINES)
	@echo "\n✅ IPA: build/ios/ipa/"

build-windows:
	flutter build windows --release $(DEFINES)
	@echo "\n✅ EXE: build/windows/x64/runner/Release/"

# ── 工具 ─────────────────────────────────────────────────────
get:
	flutter pub get

clean:
	flutter clean && flutter pub get

.PHONY: run-android run-ios run-windows build-apk build-aab build-ios build-ipa build-windows get clean

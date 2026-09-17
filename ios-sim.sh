#!/bin/bash
# 《心之世界》iOS 模拟器运行（Apple Silicon 原生 arm64）
# 背景：官方 Godot 4.7.2 iOS 导出模板的模拟器切片只含 x86_64 对象（无 arm64），
#       且 Xcode 26 的 installd 拒装纯 x86_64 应用、Rosetta 模拟器路线已实证不可行。
#       解法：本机从 4.7.2-stable 源码编译 arm64-simulator 引擎库，已合入导出模板
#       （~/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip，
#       原 zip 备份为 ios.zip.orig），导出出的 Xcode 工程可直接编原生 arm64 模拟器包。
# 用法：./ios-sim.sh [设备UDID]（缺省用当前已启动的模拟器）
set -e

GODOT="$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
REPO="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$REPO/build-output/ios"
DD="$REPO/build-output/dd-sim"
UDID="${1:-booted}"

echo "[1/4] 生成 Xcode 工程（Godot 导出）…"
"$GODOT" --headless --path "$REPO/Code" --export-debug "iOS" "$IOS_DIR/HeartOfTheWorld.ipa" >/dev/null 2>&1 || true
[ -d "$IOS_DIR/HeartOfTheWorld.xcodeproj" ] || { echo "✗ Xcode 工程未生成"; exit 3; }

# 模拟器切片自检兜底：Godot（Steam 版）优先读内嵌模板 editor_data/export_templates/，
# 两处模板 zip 都已修补；若 Godot 升级后模板被还原导致切片缺 arm64，用归档胖库补上
XCFW_SIM="$IOS_DIR/HeartOfTheWorld.xcframework/ios-arm64_x86_64-simulator"
FAT_LIB="$REPO/build-output/ios-sim-engine/libgodot.ios.template_debug.arm64+x86_64.simulator.a"
if ! ar t "$XCFW_SIM/libgodot.a" 2>/dev/null | grep -q "arm64"; then
	echo "  ⚠ 模拟器切片缺 arm64（模板被还原？），从归档胖库修复 …"
	cp "$FAT_LIB" "$XCFW_SIM/libgodot.a"
fi

echo "[2/4] 原生 arm64 模拟器构建 …"
# SWB 探测死锁保活：xcodebuild 卡 CreateBuildDescription 时由它清理（见 AGENTS 记忆）
if [ -x /tmp/hotw_probe_babysitter.sh ] && ! pgrep -f hotw_probe_babysitter >/dev/null; then
	nohup /tmp/hotw_probe_babysitter.sh >/dev/null 2>&1 &
fi
xcodebuild build \
	-project "$IOS_DIR/HeartOfTheWorld.xcodeproj" \
	-scheme HeartOfTheWorld \
	-sdk iphonesimulator -configuration Debug \
	-destination 'generic/platform=iOS Simulator' \
	-derivedDataPath "$DD" \
	CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
	> /tmp/hotw_simbuild.log 2>&1 || { tail -20 /tmp/hotw_simbuild.log; exit 3; }
APP="$DD/Build/Products/Debug-iphonesimulator/HeartOfTheWorld.app"
[ -f "$APP/HeartOfTheWorld" ] || { echo "✗ 可执行文件未生成"; exit 3; }

echo "[3/4] 本地暂存签名（绕开 iCloud 扩展属性）…"
rm -rf /tmp/HotWSim && mkdir -p /tmp/HotWSim
cp -R "$APP" /tmp/HotWSim/
xattr -cr /tmp/HotWSim/HeartOfTheWorld.app 2>/dev/null || true
find /tmp/HotWSim/HeartOfTheWorld.app \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
codesign -f -s - /tmp/HotWSim/HeartOfTheWorld.app >/dev/null 2>&1

echo "[4/4] 安装并启动（模拟器需已启动）…"
xcrun simctl install "$UDID" /tmp/HotWSim/HeartOfTheWorld.app
open -a Simulator
xcrun simctl launch "$UDID" com.linxin.heartoftheworld
echo "✓ 完成！游戏运行于 iOS 模拟器。"

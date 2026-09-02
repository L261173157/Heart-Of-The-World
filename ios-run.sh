#!/bin/bash
# 《心之世界》iOS 签名导出 + 真机安装（手动签名通道，无需 Xcode 登录账号）
# 原理：Godot 生成 Xcode 工程（其内部签名会失败，忽略）→ 无签名构建 →
#       用钥匙串开发证书 + 通配符描述文件手动 codesign → devicectl 装机。
# 前置：iPhone 用数据线连接并在手机上"信任此电脑"。
# 用法：./ios-run.sh
set -e

GODOT="$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
REPO="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$REPO/build-output/ios"
DD="$REPO/build-output/dd"
IDENTITY="Apple Development: Xin Lin (YU7FLV923J)"
TEAM="3FD979T5VV"
BUNDLE_ID="com.linxin.heartoftheworld"
PROFILE_UUID="63710279-2591-46dc-bbaa-53532db90472"
PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

if [ ! -f "$PROFILE" ]; then
	echo "✗ 找不到通配符描述文件（$PROFILE_UUID）。请在 Xcode 登录过一次团队账号以生成它。"
	exit 3
fi

echo "[1/5] 生成 Xcode 工程（Godot 内部签名失败属预期，忽略）…"
"$GODOT" --headless --path "$REPO/Code" --export-debug "iOS" "$IOS_DIR/HeartOfTheWorld.ipa" || true
if [ ! -d "$IOS_DIR/HeartOfTheWorld.xcodeproj" ]; then
	echo "✗ Xcode 工程未生成，Godot 导出异常终止。"; exit 3
fi

echo "[2/5] 无签名构建 .app …"
xcodebuild build \
	-project "$IOS_DIR/HeartOfTheWorld.xcodeproj" \
	-scheme HeartOfTheWorld \
	-sdk iphoneos -configuration Debug \
	-destination 'generic/platform=ios' \
	-derivedDataPath "$DD" \
	CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
	> /tmp/hotw_xcodebuild.log 2>&1 || { tail -20 /tmp/hotw_xcodebuild.log; exit 3; }
APP="$DD/Build/Products/Debug-iphoneos/HeartOfTheWorld.app"
[ -d "$APP" ] || { echo "✗ .app 未生成"; exit 3; }

echo "[3/5] 嵌入描述文件并生成权限清单 …"
cp "$PROFILE" "$APP/embeded.tmp" && mv "$APP/embeded.tmp" "$APP/embedded.mobileprovision"
security cms -D -i "$PROFILE" 2>/dev/null | plutil -extract Entitlements xml1 -o - - > /tmp/hotw_ent.plist
plutil -replace application-identifier -string "$TEAM.$BUNDLE_ID" /tmp/hotw_ent.plist

echo "[4/5] 手动签名（本地目录暂存，绕开 iCloud 扩展属性）…"
rm -rf /tmp/HotWSign && mkdir -p /tmp/HotWSign
cp -R "$APP" /tmp/HotWSign/
xattr -cr /tmp/HotWSign/HeartOfTheWorld.app 2>/dev/null || true
find /tmp/HotWSign/HeartOfTheWorld.app \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
codesign -f -s "$IDENTITY" --entitlements /tmp/hotw_ent.plist /tmp/HotWSign/HeartOfTheWorld.app
codesign -vv /tmp/HotWSign/HeartOfTheWorld.app
rm -rf "$REPO/build-output/signed" && mkdir -p "$REPO/build-output/signed"
cp -R /tmp/HotWSign/HeartOfTheWorld.app "$REPO/build-output/signed/"
echo "  签名产物：$REPO/build-output/signed/HeartOfTheWorld.app"

echo "[5/5] 查找已连接的 iPhone …"
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "available" \
	| grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)
# 双重校验：只接受标准 UUID 格式，防异常输出注入
if [[ ! "$DEVICE_ID" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
	DEVICE_ID=""
fi
if [ -z "$DEVICE_ID" ]; then
	echo "✓ 签名完成，但未发现已连接设备。"
	echo  "  连接 iPhone（并在手机上信任）后重新运行本脚本即可安装。"
	exit 2
fi
xcrun devicectl device install app --device "$DEVICE_ID" "$REPO/build-output/signed/HeartOfTheWorld.app"

echo "✓ 完成！在 iPhone 主屏启动 Heart Of The World。"
echo "  首次启动若提示未受信任：设置 → 通用 → VPN与设备管理 → 信任 Shanghai Qiming Wujie 开发者。"

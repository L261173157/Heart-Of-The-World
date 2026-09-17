#!/bin/bash
# 《心之世界》iOS TestFlight/App Store 上传通道（Release 构建 + 分发签名）
# 与 ios-run.sh（开发签名真机试玩）互补：
#   Godot --export-release 生成 Xcode 工程 → xcodebuild archive（自动签名，首次自动注册
#   App ID 并生成描述文件）→ exportArchive 以 app-store 方式重签出 ipa → 可选 altool 上传。
# 前置：
#   - Xcode 已登录团队成员账号（开发者后台注册 App ID 用）
#   - App Store Connect 已创建 App 记录（首次上传前必须，否则 altool 报
#     "No suitable application record found"）
# 用法：
#   ./ios-upload.sh    # 一条龙：导出 → 签名 → 校验 → 经 Xcode 会话上传（无需密码）
# 前置：Xcode 已登录团队成员账号（上传认证走该会话，2026-09-04 实证可行）
# 安全约束：对外上传属发布操作，Agent 不得自动执行，每次须用户当次确认。
# build 号自动递增（build-output/upload_build_number），同版本号下每次上传统计唯一。
set -e

GODOT="$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
REPO="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$REPO/build-output/ios-release"
# Archive/DerivedData 必须放 /tmp：仓库在 iCloud 路径，codesign 会报 "detritus not allowed"
# （见 开发计划.md 真机签名一节的同款坑）
TMP_ROOT="/tmp/hotw_upload_build"
DD="$TMP_ROOT/dd"
ARCHIVE="$TMP_ROOT/HeartOfTheWorld.xcarchive"
UPLOAD_DIR="$REPO/build-output/upload"
TEAM="3FD979T5VV"                       # 上海启明无界（分发团队）
BUNDLE_ID="com.linxin.heartoftheworld"
BUILD_NUM_FILE="$REPO/build-output/upload_build_number"

if [ -f "$BUILD_NUM_FILE" ]; then BUILD_NUM=$(cat "$BUILD_NUM_FILE"); else BUILD_NUM=1; fi
# 防御：build 号只允许纯数字，防本地文件被污染后注入后续命令
if ! [[ "$BUILD_NUM" =~ ^[0-9]+$ ]]; then BUILD_NUM=1; fi

echo "[1/6] 生成 Xcode 工程（Release）…"
rm -rf "$IOS_DIR" && mkdir -p "$IOS_DIR"
"$GODOT" --headless --path "$REPO/Code" --export-release "iOS" "$IOS_DIR/HeartOfTheWorld.ipa" || true
[ -d "$IOS_DIR/HeartOfTheWorld.xcodeproj" ] || { echo "✗ Xcode 工程未生成，Godot 导出异常终止。"; exit 3; }

echo "[2/6] build 号 $BUILD_NUM (CURRENT_PROJECT_VERSION 注入，Xcode 会用它覆盖 plist 内的 CFBundleVersion)"

echo "[3/6] Archive（自动签名；首次运行会自动注册 App ID / 生成描述文件，需联网）…"
xcodebuild archive \
	-project "$IOS_DIR/HeartOfTheWorld.xcodeproj" \
	-scheme HeartOfTheWorld \
	-configuration Release \
	-destination 'generic/platform=iOS' \
	-archivePath "$ARCHIVE" \
	-derivedDataPath "$DD" \
	DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
	CURRENT_PROJECT_VERSION="$BUILD_NUM" \
	-allowProvisioningUpdates \
	> /tmp/hotw_archive.log 2>&1 || { tail -30 /tmp/hotw_archive.log; exit 3; }

echo "[4/6] 导出 App Store 分发签名 ipa …"
cat > /tmp/hotw_export_options.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store</string>
	<key>teamID</key><string>3FD979T5VV</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>compileBitcode</key><false/>
</dict>
</plist>
EOF
rm -rf "$UPLOAD_DIR" && mkdir -p "$UPLOAD_DIR"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE" \
	-exportOptionsPlist /tmp/hotw_export_options.plist \
	-exportPath "$UPLOAD_DIR" \
	-allowProvisioningUpdates \
	> /tmp/hotw_export.log 2>&1 || { tail -30 /tmp/hotw_export.log; exit 3; }
IPA="$UPLOAD_DIR/HeartOfTheWorld.ipa"
[ -f "$IPA" ] || { echo "✗ ipa 未生成（见 /tmp/hotw_export.log）"; exit 3; }

echo "$((BUILD_NUM + 1))" > "$BUILD_NUM_FILE"

# dSYM 拷回仓库（/tmp 重启即清空），TestFlight 崩溃符号化时在 ASC 上传
[ -d "$ARCHIVE/dSYMs" ] && cp -R "$ARCHIVE/dSYMs" "$UPLOAD_DIR/"

echo "[5/6] 校验分发签名（get-task-allow 应为 false）…"
rm -rf /tmp/hotw_ipa_check && mkdir -p /tmp/hotw_ipa_check
unzip -q "$IPA" "Payload/*.app/embedded.mobileprovision" -d /tmp/hotw_ipa_check
PROFILE_FILE=$(find /tmp/hotw_ipa_check -name "embedded.mobileprovision" | head -1)
security cms -D -i "$PROFILE_FILE" 2>/dev/null > /tmp/hotw_ipa_check/prof.plist
PROFILE_NAME=$(plutil -extract Name raw -o - /tmp/hotw_ipa_check/prof.plist 2>/dev/null)
GET_TASK=$(plutil -extract Entitlements.get-task-allow raw -o - /tmp/hotw_ipa_check/prof.plist 2>/dev/null)
echo "  描述文件: $PROFILE_NAME (get-task-allow=$GET_TASK)"
[ "$GET_TASK" = "false" ] || { echo "✗ 仍是开发签名，不能上传 App Store Connect。"; exit 3; }
echo "  ipa: $IPA (dSYM 在 $UPLOAD_DIR/dSYMs，TestFlight 崩溃符号化用)"

echo "[6/6] 上传（经 Xcode 已登录会话，无需 App 专用密码）…"
cat > "$TMP_ROOT/upload_opts.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>3FD979T5VV</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>compileBitcode</key><false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE" \
	-exportOptionsPlist "$TMP_ROOT/upload_opts.plist" \
	-exportPath "$TMP_ROOT/upload_out" \
	-allowProvisioningUpdates \
	> /tmp/hotw_upload.log 2>&1 || {
		if grep -q "Failed to Use Accounts" /tmp/hotw_upload.log; then
			echo "✗ Xcode 无 App Store Connect 登录会话（2026-09-13 实证：账号被登出后 keychain 连 Xcode-Token 都没有）。"
			echo "  修复：打开 Xcode → Settings… → Apple Accounts 重新登录 Apple ID（密码+双重认证），"
			echo "  然后只需重跑第 6 步（archive 与 ipa 都已就绪，不必整体重来）。"
		else
			tail -30 /tmp/hotw_upload.log
		fi
		exit 3
	}
echo "✓ 上传完成。ASC 处理 10–30 分钟后出现在 TestFlight，内部测试组自动分发。"

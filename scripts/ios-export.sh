#!/bin/bash
# 由装机脚本 source：每次只消费自己的空目录，任意导出失败均停止。
# preset 使用 export_project_only，签名只在调用方执行，毋须吞签名错误。
hotw_export_debug_project() {
	mkdir -p "$REPO/build-output"
	IOS_RUN_DIR="$(mktemp -d "$REPO/build-output/ios-debug.XXXXXX")" || return 3
	IOS_DIR="$IOS_RUN_DIR/export"
	DD="$IOS_RUN_DIR/derived-data"
	mkdir -p "$IOS_DIR"
	if ! "$GODOT" --headless --path "$REPO/Code" --export-debug "iOS" "$IOS_DIR/HeartOfTheWorld.ipa" >"$IOS_RUN_DIR/export.log" 2>&1; then
		cat "$IOS_RUN_DIR/export.log"
		echo "✗ 本轮导出失败，已停止；未使用旧工程。日志：$IOS_RUN_DIR/export.log"
		return 3
	fi
	python3 "$REPO/scripts/verify-ios-export.py" "$REPO" "$IOS_DIR" || return 3
	echo "  本轮导出：$IOS_DIR（版本与 PCK 指纹见 export-manifest.json）"
}

#!/usr/bin/env bash
set -euo pipefail

# ironset — macOS 文件类型默认应用绑定工具
# 用法: ironset <扩展名> <应用名>
# 示例: ironset md Typora

setapp() {
    local ext="$1"
    local app_name="$2"

    if [[ -z "$ext" || -z "$app_name" ]]; then
        echo "用法: ironset <扩展名> <应用名>" >&2
        echo "示例: ironset md Typora" >&2
        return 1
    fi

    local app_path
    if [[ "$app_name" == *.app ]]; then
        app_path="/Applications/$app_name"
    else
        app_path="/Applications/${app_name}.app"
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "未找到: $app_path，尝试搜索…" >&2
        app_path=$(mdfind "kMDItemKind == 'Application'" 2>/dev/null |
            grep -i "/${app_name}.app$" | head -1)
        if [[ -z "$app_path" ]]; then
            echo "错误: 找不到应用 '$app_name'" >&2
            return 1
        fi
        echo "已在 $app_path 找到"
    fi

    local bundle_id
    bundle_id=$(mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null)
    if [[ -z "$bundle_id" ]]; then
        echo "错误: 无法获取 bundle identifier（$app_path）" >&2
        return 1
    fi
    echo "→ Bundle ID: $bundle_id"

    local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    echo "→ 停止图标相关服务…"
    killall iconservicesagent 2>/dev/null || true
    killall Dock 2>/dev/null || true

    echo "→ 绑定 .${ext} → $bundle_id（all）"
    duti -s "$bundle_id" ".${ext}" all

    echo "→ 如果弹出系统确认对话框，请点击「允许」后按回车继续..."
    read -r

    echo "→ 强制扫描应用包…"
    "$lsreg" -f "$app_path"

    echo "→ 更新时间戳并重新注册…"
    touch "$app_path"
    "$lsreg" -f "$app_path"

    echo "→ 重建 Launch Services 数据库…"
    "$lsreg" -kill -seed -r -domain local -domain system -domain user

    echo "→ 清理图标磁盘缓存…"
    sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    sudo find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} \; 2>/dev/null || true

    echo "→ 重启 Finder…"
    killall Finder 2>/dev/null || true
}

setapp "$@"

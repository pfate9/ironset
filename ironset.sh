#!/usr/bin/env bash
set -euo pipefail

# ironset — macOS 文件类型默认应用绑定工具
# 用法: ironset <扩展名> <应用名>
# 示例: ironset md Typora

usage() {
    echo "用法: ironset <扩展名> <应用名>" >&2
    echo "示例: ironset md Typora" >&2
    echo "       ironset py 'Visual Studio Code'" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "错误: 缺少依赖 '$command_name'" >&2
        return 1
    fi
}

main() {
    if [[ $# -ne 2 ]]; then
        usage
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "错误: ironset 仅支持 macOS" >&2
        return 1
    fi

    require_command duti
    require_command mdfind
    require_command mdls

    local ext="$1"
    local app_name="$2"

    if [[ -z "$ext" || -z "$app_name" ]]; then
        usage
    fi

    # 补全 .app 后缀
    local app_path
    if [[ "$app_name" == *.app ]]; then
        app_path="/Applications/$app_name"
    else
        app_path="/Applications/${app_name}.app"
    fi

    if [[ ! -d "$app_path" ]]; then
        echo "未找到: ${app_path}，尝试搜索…" >&2
        app_path=$(
            mdfind "kMDItemKind == 'Application'" 2>/dev/null |
                grep -i "/${app_name}.app$" |
                head -1 || true
        )
        if [[ -z "$app_path" ]]; then
            echo "错误: 找不到应用 '$app_name'" >&2
            return 1
        fi
        echo "已在 $app_path 找到"
    fi

    # 获取 bundle identifier
    local bundle_id
    bundle_id=$(mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null)
    if [[ -z "$bundle_id" ]]; then
        echo "错误: 无法获取 bundle identifier（${app_path}）" >&2
        return 1
    fi
    echo "→ Bundle ID: ${bundle_id}"

    local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    if [[ ! -x "$lsreg" ]]; then
        echo "错误: 找不到 lsregister" >&2
        return 1
    fi

    # 1. 先停止图标服务和 Dock，防止它们在后续步骤中缓存旧数据
    echo "→ 停止图标相关服务…"
    killall iconservicesagent 2>/dev/null || true
    killall Dock 2>/dev/null || true

    # 2. duti 绑定
    echo "→ 绑定 .${ext} → ${bundle_id}（all）"
    duti -s "$bundle_id" ".${ext}" all

    # 3. 强制扫描应用包
    echo "→ 强制扫描应用包…"
    "$lsreg" -f "$app_path"

    # 4. 更新时间戳再注册（防止因时间戳太旧被跳过）
    echo "→ 更新时间戳并重新注册…"
    touch "$app_path"
    "$lsreg" -f "$app_path"

    # 5. 重置并重建 Launch Services 数据库
    #    -kill: 先清空数据库，再执行后续操作（防止旧绑定残留）
    #    -seed: 从零扫描，而非增量更新
    echo "→ 重建 Launch Services 数据库…"
    "$lsreg" -kill -seed -r -domain local -domain system -domain user

    # 6. 清理图标磁盘缓存（否则服务重启后会直接从缓存加载旧图标）
    echo "→ 清理图标磁盘缓存…"
    sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    sudo find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} \; 2>/dev/null || true

    # 7. 重启 Finder（Dock 和 iconservicesagent 会随 Finder 自动重启，此时数据库和缓存都是干净的）
    echo "→ 重启 Finder…"
    killall Finder 2>/dev/null || true
}

main "$@"

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

log() {
    printf '→ %s\n' "$*"
}

die() {
    printf '错误: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf "缺少依赖 '%s'\n" "$command_name" >&2
        return 1
    fi
}

require_commands() {
    local command_name
    local missing=0

    for command_name in "$@"; do
        require_command "$command_name" || missing=1
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi
}

find_app() {
    local app_name="$1"
    local app_bundle="$app_name"

    if [[ "$app_bundle" != *.app ]]; then
        app_bundle="${app_bundle}.app"
    fi

    local app_bundle_lower
    app_bundle_lower="$(printf '%s' "$app_bundle" | tr '[:upper:]' '[:lower:]')"
    local candidate
    for candidate in \
        "/Applications/${app_bundle}" \
        "${HOME}/Applications/${app_bundle}" \
        "/System/Applications/${app_bundle}"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    while IFS= read -r candidate; do
        if [[ "$(basename "$candidate" | tr '[:upper:]' '[:lower:]')" == "$app_bundle_lower" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(mdfind "kMDItemKind == 'Application'" 2>/dev/null)

    return 1
}

main() {
    if [[ $# -ne 2 ]]; then
        usage
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        die "ironset 仅支持 macOS"
    fi

    require_commands duti mdfind mdls

    local ext="$1"
    local app_name="$2"
    ext="${ext#.}"

    if [[ -z "$ext" || -z "$app_name" ]]; then
        usage
    fi

    local app_path
    if ! app_path="$(find_app "$app_name")"; then
        die "找不到应用 '$app_name'"
    fi

    if [[ "$app_path" != "/Applications/"* ]]; then
        echo "已在 $app_path 找到"
    fi

    local bundle_id
    bundle_id=$(mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null)
    if [[ -z "$bundle_id" || "$bundle_id" == "(null)" ]]; then
        die "无法获取 bundle identifier（${app_path}）"
    fi
    log "Bundle ID: ${bundle_id}"

    local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    if [[ ! -x "$lsreg" ]]; then
        die "找不到 lsregister"
    fi

    # 1. 先停止图标服务和 Dock，防止它们在后续步骤中缓存旧数据
    log "停止图标相关服务…"
    killall iconservicesagent 2>/dev/null || true
    killall Dock 2>/dev/null || true

    # 2. duti 绑定
    log "绑定 .${ext} → ${bundle_id}（all）"
    duti -s "$bundle_id" ".${ext}" all

    # 3. 强制扫描应用包
    log "强制扫描应用包…"
    "$lsreg" -f "$app_path"

    # 4. 重置并重建 Launch Services 数据库
    #    -kill: 先清空数据库，再执行后续操作（防止旧绑定残留）
    #    -seed: 从零扫描，而非增量更新
    log "重建 Launch Services 数据库…"
    "$lsreg" -kill -seed -r -domain local -domain system -domain user

    # 5. 清理图标磁盘缓存（否则服务重启后会直接从缓存加载旧图标）
    log "清理图标磁盘缓存…"
    sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    sudo find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} \; 2>/dev/null || true

    # 6. 重启 Finder（Dock 和 iconservicesagent 会随 Finder 自动重启，此时数据库和缓存都是干净的）
    log "重启 Finder…"
    killall Finder 2>/dev/null || true
}

main "$@"

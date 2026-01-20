#!/usr/bin/env bash
set -Eeuo pipefail

#######################################
# 基本参数
#######################################
COMMAND="${1:-}"
CONFIG_FILE="${2:-subtrees.conf}"

#######################################
# 工具函数
#######################################
die() {
    echo "[ERROR] $*" >&2
    exit 1
}

info() {
    echo "[INFO ] $*"
}

action() {
    echo "[DO   ] $*"
}

skip() {
    echo "[SKIP ] $*"
}

usage() {
    cat <<EOF
用法:
  $0 add    [config_file]
  $0 pull   [config_file]
  $0 remove [config_file]

默认配置文件: subtrees.conf
EOF
    exit 1
}

#######################################
# 前置检查
#######################################
[[ -z "$COMMAND" ]] && usage
[[ ! -f "$CONFIG_FILE" ]] && die "配置文件不存在: $CONFIG_FILE"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "当前目录不是 git 仓库"

git subtree --help >/dev/null 2>&1 \
    || die "git subtree 不可用，请先安装 git-subtree"

#######################################
# 读取配置
#######################################
declare -A CFG_REPO
declare -A CFG_BRANCH
declare -A CFG_PREFIX

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    IFS='|' read -r prefix repo branch <<< "$line"

    prefix="$(echo "$prefix" | xargs)"
    repo="$(echo "$repo" | xargs)"
    branch="$(echo "$branch" | xargs)"

    [[ -z "$prefix" || -z "$repo" || -z "$branch" ]] && \
        die "配置格式错误: $line"

    CFG_PREFIX["$prefix"]=1
    CFG_REPO["$prefix"]="$repo"
    CFG_BRANCH["$prefix"]="$branch"
done < "$CONFIG_FILE"

#######################################
# add / pull
#######################################
if [[ "$COMMAND" == "add" || "$COMMAND" == "pull" ]]; then
    for prefix in "${!CFG_PREFIX[@]}"; do
        repo="${CFG_REPO[$prefix]}"
        branch="${CFG_BRANCH[$prefix]}"

        if [[ "$COMMAND" == "add" ]]; then
            if [[ -d "$prefix" ]]; then
                skip "$prefix 已存在"
                continue
            fi
            git reset --hard HEAD
            git clean -fdx
            action "subtree add $prefix <= $repo ($branch)"
            git subtree add \
                --prefix="$prefix" \
                "$repo" \
                "$branch" \
                --squash
        fi

        if [[ "$COMMAND" == "pull" ]]; then
            if [[ ! -d "$prefix" ]]; then
                skip "$prefix 不存在"
                continue
            fi

            action "subtree pull $prefix <= $repo ($branch)"
            git subtree pull \
                --prefix="$prefix" \
                "$repo" \
                "$branch" \
                --squash
        fi
    done
fi

#######################################
# remove（声明式收敛）
#######################################
if [[ "$COMMAND" == "remove" ]]; then
    info "以配置文件为准，删除根目录下未声明的一级 subtree"

    removed=0

    # 只列出仓库根目录的一级目录
    for dir in */ ; do
        dir="${dir%/}"  # 去掉末尾的 /
        [[ -z "$dir" ]] && continue

        # 如果配置里没有声明，就删除
        [[ -z "${CFG_PREFIX[$dir]:-}" ]] && {
            action "删除未声明 subtree: $dir"
            git rm -r "$dir"
            removed=1
        } || skip "$dir 在配置中，保留"
    done

    if [[ "$removed" -eq 1 ]]; then
        git commit -m "chore: remove unmanaged subtrees"
    else
        info "无未声明 subtree，仓库已收敛"
    fi
fi

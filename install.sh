#!/bin/bash
# 安装/同步状态栏脚本到 ~/.claude，并只合并 settings.json 中的 statusLine 字段（保留其他配置）
set -e
src="$(cd "$(dirname "$0")" && pwd)"
dst="$HOME/.claude"
command -v jq >/dev/null || { echo "需要先安装 jq"; exit 1; }
mkdir -p "$dst"
install -m 700 "$src/statusline-command.sh" "$src/statusline-fable-refresh.sh" "$dst/"
[ -f "$dst/settings.json" ] || echo '{}' >"$dst/settings.json"
tmp=$(mktemp)
jq --arg cmd "sh $dst/statusline-command.sh" \
  '.statusLine = {type: "command", command: $cmd, padding: 0, refreshInterval: 1}' \
  "$dst/settings.json" >"$tmp" && mv "$tmp" "$dst/settings.json"
echo "已安装到 $dst"

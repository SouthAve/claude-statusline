#!/bin/bash
# 把 ~/.claude 下的状态栏脚本同步回本仓库，有变化时提交并推送
# 用法：./sync.sh ["提交说明"]
set -e
cd "$(dirname "$0")"
for f in statusline-command.sh statusline-fable-refresh.sh; do
  cp "$HOME/.claude/$f" "./$f"
done
if [ -z "$(git status --porcelain)" ]; then echo "没有变化"; exit 0; fi
git --no-pager diff --stat
git add -A
git commit -q -m "${1:-chore: sync statusline scripts}"
git push -q && echo "已推送：$(git log --oneline -1)"

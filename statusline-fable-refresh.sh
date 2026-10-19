#!/bin/bash
# 后台刷新 Fable 独立周额度缓存：由状态栏脚本在缓存过期时异步调用，自身不输出任何内容。
# 令牌仅在内存中用于本次请求，不写入文件、不打印；缓存只保存百分比与重置时间。
state_dir="${STATUSLINE_STATE_DIR:-$HOME/.claude/statusline-state}"
cache="$state_dir/fable"
lock="$state_dir/fable.lock"
mkdir -p "$state_dir" && chmod 700 "$state_dir"
umask 077

# 单实例锁；锁超过 60 秒视为残留并清理
if ! mkdir "$lock" 2>/dev/null; then
  [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$lock" 2>/dev/null
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT
touch "$state_dir/fable.attempt"   # 无论成败都记录尝试时间，用于失败退避

# 读取 OAuth 访问令牌：macOS 钥匙串优先，其次 Linux 凭据文件
cred=""
if command -v security >/dev/null 2>&1; then
  cred=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
fi
[ -z "$cred" ] && [ -r "$HOME/.claude/.credentials.json" ] && cred=$(cat "$HOME/.claude/.credentials.json")
token=$(printf '%s' "$cred" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
cred=""
[ -n "$token" ] || exit 0

resp=$(curl -sS -m 10 -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" -H "Content-Type: application/json" \
  https://api.anthropic.com/api/oauth/usage 2>/dev/null)
token=""
[ -n "$resp" ] || exit 0

line=$(printf '%s' "$resp" | jq -r '
  [.limits[]? | select(.kind == "weekly_scoped"
      and ((.scope.model.display_name // "") | ascii_downcase | startswith("fable")))][0]
  | select(. != null and .percent != null and .resets_at != null)
  | "\(.percent) \(.resets_at | sub("\\.[0-9]+"; "") | sub("[+-]00:00$"; "Z") | fromdateiso8601)"' 2>/dev/null)
resp=""
case "$line" in
  [0-9]*" "[0-9]*) printf '%s %s\n' "$line" "$(date +%s)" >"$cache.tmp.$$" && mv "$cache.tmp.$$" "$cache" ;;
esac
exit 0

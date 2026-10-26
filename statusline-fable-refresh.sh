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
# 5h/7d 限额：仅当状态栏传入 STATUSLINE_RL_CACHE（默认登录账号会话，令牌与该账号一致）时才写入；
# 格式与状态栏的限额缓存一致，at 为写入时间；任一窗口缺失或非法则整体放弃，保留原缓存
rl_json=""
if [ -n "$STATUSLINE_RL_CACHE" ]; then
  rl_json=$(printf '%s' "$resp" | jq -c --argjson at "$(date +%s)" '
    def win($w): $w | select(. != null and .utilization != null and .resets_at != null)
      | {used_percentage: (.utilization | round),
         resets_at: (.resets_at | sub("\\.[0-9]+"; "") | sub("[+-]00:00$"; "Z") | fromdateiso8601)};
    {five_hour: win(.five_hour), seven_day: win(.seven_day), at: $at}' 2>/dev/null)
fi
resp=""
case "$line" in
  [0-9]*" "[0-9]*) printf '%s %s\n' "$line" "$(date +%s)" >"$cache.tmp.$$" && mv "$cache.tmp.$$" "$cache" ;;
esac
case "$rl_json" in
  '{"five_hour":{"used_percentage":'[0-9]*'"seven_day":{"used_percentage":'[0-9]*'"at":'[0-9]*'}')
    printf '%s\n' "$rl_json" >"$STATUSLINE_RL_CACHE.$$" && mv -f "$STATUSLINE_RL_CACHE.$$" "$STATUSLINE_RL_CACHE" ;;
esac
exit 0

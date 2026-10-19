#!/bin/bash
# Claude Code 状态栏：固定两行，不按宽度裁剪（限额并入第 2 行末尾）
# 若被 sh 调用则切换到 bash 重新执行（stdin 保持不变）
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

command -v jq >/dev/null 2>&1 || { echo "statusline: 需要安装 jq"; exit 0; }
input=$(cat)

# ---- 一次 jq 解析主要字段（缺失统一为空串，绝不输出 null）----
US=$'\x1f'
IFS=$US read -r model effort dir repo used ctx_size ctx_tokens dur_ms cost add del \
  five five_r week week_r spend_pct spend_used spend_lim sid cu_in cu_cc cu_cr <<<"$(printf '%s' "$input" | jq -r '
  [ .model.display_name, .effort.level, (.workspace.current_dir // .cwd),
    (.workspace.repo | if . then .owner + "/" + .name else null end),
    .context_window.used_percentage, .context_window.context_window_size,
    .context_window.total_input_tokens,
    .cost.total_duration_ms, .cost.total_cost_usd,
    .cost.total_lines_added, .cost.total_lines_removed,
    .rate_limits.five_hour.used_percentage, .rate_limits.five_hour.resets_at,
    .rate_limits.seven_day.used_percentage, .rate_limits.seven_day.resets_at,
    .rate_limits.spend_limit.used_percentage, .rate_limits.spend_limit.used_usd,
    .rate_limits.spend_limit.limit_usd,
    .session_id, .context_window.current_usage.input_tokens,
    .context_window.current_usage.cache_creation_input_tokens,
    .context_window.current_usage.cache_read_input_tokens
  ] | map(if . == null then "" else tostring end) | join("\u001f")' 2>/dev/null)"

# ---- 颜色（256 色低饱和）----
c() { printf '\033[38;5;%sm' "$1"; }
RST=$'\033[0m'
DIM=$(c 242)
C_MODEL=$(c 110); C_EFFORT=$(c 146); C_REPO=$(c 179); C_DIR=$(c 249)
C_BRANCH=$(c 139); C_DIRTY=$(c 173); C_INFO=$(c 109); C_LIM=$(c 73)
C_OK=$(c 108); C_WARN=$(c 179); C_BAD=$(c 167)
C_5H=$(c 73); C_7D=$(c 97); C_XL=$(c 103)   # 限额进度条：青 / 紫 / 蓝灰，不随百分比变色

level_color() { # $1 = 百分比整数
  if [ "$1" -ge 80 ]; then printf '%s' "$C_BAD"
  elif [ "$1" -ge 50 ]; then printf '%s' "$C_WARN"
  else printf '%s' "$C_OK"; fi
}

# ---- 行构建：依次追加，完整显示，不做宽度裁剪 ----
line=""; linew=0
addf() { # $1 颜色  $2 文本
  [ -z "$2" ] && return 1
  [ "$linew" -gt 0 ] && line+=" ${DIM}│${RST} "
  line+="${1}${2}${RST}"
  linew=1
  return 0
}
flush() { [ -n "$line" ] && printf '%s\n' "$line"; line=""; linew=0; }
isint() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

fmt_ts() { date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null; }
fmt_tok() {
  local n=${1%.*}
  isint "$n" || return 0
  if [ "$n" -ge 1000000 ]; then printf '%d.%dM' $((n / 1000000)) $((n % 1000000 / 100000))
  elif [ "$n" -ge 1000 ]; then printf '%dk' $((n / 1000))
  else printf '%d' "$n"; fi
}
fmt_dur() {
  local s=$(( ${1%.*} / 1000 ))
  if [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ]; then printf '%dm' $((s / 60))
  else printf '%ds' "$s"; fi
}
fmt_cd() { # 倒计时
  local d=$(( ${1%.*} - $(date +%s) ))
  if [ "$d" -le 0 ]; then printf 'now'
  elif [ "$d" -ge 86400 ]; then printf '%dd%dh' $((d / 86400)) $((d % 86400 / 3600))
  elif [ "$d" -ge 3600 ]; then printf '%dh%02dm' $((d / 3600)) $((d % 3600 / 60))
  else printf '%dm' $(((d + 59) / 60)); fi
}

# 限额片段：$1 标签 $2 百分比 $3 重置epoch $4 时间格式
limit_seg() {
  local p r="" long col="${5:-$C_XL}"
  [ -n "$2" ] || return 0
  p=$(printf '%.0f' "$2" 2>/dev/null) || return 0
  isint "$p" || return 0
  long="$1 ${p}%"
  if isint "${3%.*}" && [ -n "$3" ]; then
    r=$(fmt_cd "$3")
    long="$long ↻$(fmt_ts "${3%.*}" "$4") ($r)"
  fi
  addf "$col" "$long"
}

# ================= 第 1 行：模型 / Effort / 目录 / 分支 / 仓库 / ctx =================
addf "$C_MODEL" "$model"
addf "$C_EFFORT" "${effort:+✦ $effort}"
[ -n "$dir" ] && addf "$C_DIR" "📁 $(basename "$dir")"

branch=""; dirty=""
if [ -n "$dir" ] && [ -d "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -n "$branch" ] && [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null | head -n 1)" ]; then
    dirty=1
  fi
fi
diffstat=""
if isint "$add" || isint "$del"; then diffstat="(+${add:-0} -${del:-0})"; fi
if [ -n "$branch" ]; then
  btxt="⎇ $branch"
  [ -n "$dirty" ] && btxt+=" ●"
  # 增删行数并入分支片段，保持原绿色
  [ -n "$diffstat" ] && btxt+=" ${C_OK}${diffstat}"
  addf "$C_BRANCH" "$btxt"
elif [ -n "$diffstat" ]; then
  addf "$C_OK" "$diffstat"
fi
addf "$C_REPO" "$repo"

pct=""
if [ -n "$used" ]; then pct=$(printf '%.0f' "$used" 2>/dev/null); fi
bar=""
if isint "$pct"; then
  filled=$((pct / 10)); [ "$filled" -gt 10 ] && filled=10
  ctxc=$(level_color "$pct"); ptxt="${pct}%"
else
  filled=0; ctxc=$DIM; ptxt='--%'
fi
i=0; while [ "$i" -lt 10 ]; do
  if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
  i=$((i + 1))
done
tk=$(fmt_tok "$ctx_tokens"); sz=$(fmt_tok "$ctx_size")
tokpart=""
if [ -n "$tk" ] && [ -n "$sz" ]; then tokpart="$tk/$sz"
elif [ -n "$tk" ]; then tokpart="$tk"; fi
ctxtxt="ctx $bar $ptxt"
[ -n "$tokpart" ] && ctxtxt+=" (${tokpart})"
addf "$ctxc" "$ctxtxt"
flush

# ================= 第 2 行：Cache / 耗时 / 费用 / 限额 =================

# ---- Cache 命中率 + 1 小时 TTL 倒计时 ----
# 状态文件按 session_id 哈希隔离；签名(三个 token 数)变化才重置时间戳
now=$(date +%s)
state_dir="${STATUSLINE_STATE_DIR:-$HOME/.claude/statusline-state}"
sid_hash=$(printf '%s' "${sid:-default}" | cksum | cut -d' ' -f1)
state_file="$state_dir/cache-$sid_hash"
st_sig=""; st_ts=""; st_pct=""
if [ -f "$state_file" ]; then
  read -r s_sig s_ts s_pct <"$state_file" 2>/dev/null
  case "$s_sig" in
    [0-9]*:[0-9]*:[0-9]*) ;;
    *) s_sig="" ;;
  esac
  if [ -n "$s_sig" ] && isint "$s_ts" && isint "$s_pct" && [ "$s_pct" -le 100 ] \
    && [ "$s_ts" -le "$((now + 60))" ] && [ -z "${s_sig//[0-9:]/}" ]; then
    st_sig=$s_sig; st_ts=$s_ts; st_pct=$s_pct
  fi
fi
c_pct=""; c_ts=""; cache_seg=""
if isint "$cu_in" && isint "$cu_cc" && isint "$cu_cr" && [ $((cu_in + cu_cc + cu_cr)) -gt 0 ]; then
  sig="$cu_in:$cu_cc:$cu_cr"
  c_pct=$((cu_cr * 100 / (cu_in + cu_cc + cu_cr)))
  if [ "$sig" = "$st_sig" ]; then
    c_ts=$st_ts
  else
    c_ts=$now
    if mkdir -p "$state_dir" 2>/dev/null && chmod 700 "$state_dir" 2>/dev/null; then
      printf '%s %s %s\n' "$sig" "$c_ts" "$c_pct" >"$state_file.$$" 2>/dev/null \
        && mv -f "$state_file.$$" "$state_file" 2>/dev/null
    fi
  fi
elif [ -n "$st_sig" ]; then
  c_pct=$st_pct; c_ts=$st_ts   # 首次响应前：回退到上次保存的命中率
fi
if [ -n "$c_pct" ]; then
  el=$((now - c_ts)); [ "$el" -lt 0 ] && el=0
  if [ "$c_pct" -ge 50 ]; then hc=$C_OK; else hc=$DIM; fi
  if [ "$el" -gt 3600 ]; then tt="exp"; tc=$DIM
  else
    rem=$((3600 - el))
    tt=$(printf '%02d:%02d' $((rem / 60)) $((rem % 60)))
    if [ "$el" -lt 1200 ]; then tc=$C_OK
    elif [ "$el" -lt 2400 ]; then tc=$C_WARN
    elif [ "$el" -lt 3300 ]; then tc=$C_BAD
    else tc=$'\033[5m'$C_BAD; fi
  fi
  cache_seg="${hc}Cache ${c_pct}%${RST} ${tc}${tt}${RST}"
fi

# Cache 单独成片段；费用与耗时合成一个片段（两个空格相连），各自保持原颜色
[ -n "$cache_seg" ] && addf "" "$cache_seg"
dur_seg=""; cost_seg=""
isint "${dur_ms%.*}" && dur_seg="${C_INFO}⏱ $(fmt_dur "$dur_ms")${RST}"
[ -n "$cost" ] && c2=$(printf '~$%.2f' "$cost" 2>/dev/null) && [ -n "$c2" ] && cost_seg="${C_INFO}${c2}${RST}"
if [ -n "$cost_seg" ] && [ -n "$dur_seg" ]; then addf "" "${cost_seg}  ${dur_seg}"
elif [ -n "$cost_seg" ]; then addf "" "$cost_seg"
elif [ -n "$dur_seg" ]; then addf "" "$dur_seg"
fi

# ---- 限额并入第 2 行末尾（仅存在数据时显示）----
limit_seg "5h" "$five" "$five_r" "%H:%M" "$C_5H"
limit_seg "7d" "$week" "$week_r" "%m/%d %H:%M" "$C_7D"
# Fable 独立周额度：只读本地私有缓存；过期时后台异步刷新，绝不阻塞显示
fable_cache="$state_dir/fable"
fb_pct=""; fb_reset=""; fb_at=0
if [ -f "$fable_cache" ] && [ ! -L "$fable_cache" ]; then
  read -r fb_pct fb_reset fb_at <"$fable_cache" 2>/dev/null
  if ! { isint "${fb_pct%.*}" && isint "$fb_reset" && isint "$fb_at"; }; then fb_pct=""; fb_reset=""; fb_at=0; fi
fi
now_ts=$(date +%s)
attempt_at=$(stat -f %m "$state_dir/fable.attempt" 2>/dev/null || stat -c %Y "$state_dir/fable.attempt" 2>/dev/null)
isint "$attempt_at" || attempt_at=0
# 缓存超过 5 分钟、或其重置时间已过，且距上次尝试超过 60 秒才触发后台刷新
if { [ $((now_ts - fb_at)) -ge 300 ] || { [ -n "$fb_reset" ] && [ "$fb_reset" -le "$now_ts" ]; }; } \
   && [ $((now_ts - attempt_at)) -ge 60 ] && [ -x "$HOME/.claude/statusline-fable-refresh.sh" ]; then
  STATUSLINE_STATE_DIR="$state_dir" nohup "$HOME/.claude/statusline-fable-refresh.sh" >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null
fi
# 窗口已重置则不显示过期数据，等待后台刷新
if [ -n "$fb_pct" ] && [ "$fb_reset" -gt "$now_ts" ]; then
  limit_seg "fable" "$fb_pct" "" "" "$C_XL"
fi
if [ -n "$spend_used" ] && [ -n "$spend_lim" ]; then
  addf "$C_LIM" "$(printf 'spend $%.0f/$%.0f' "$spend_used" "$spend_lim" 2>/dev/null)"
elif [ -n "$spend_pct" ]; then
  limit_seg "spend" "$spend_pct" "" ""
fi
flush
exit 0

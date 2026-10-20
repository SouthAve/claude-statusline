# claude-statusline

![cc-statusline-styled](README.assets/cc-statusline-styled.png)

Claude Code 两行状态栏（Bash + jq）。

- 第 1 行：模型、思考程度、目录、Git 分支/改动、ctx 用量
- 第 2 行：Cache 命中率与 TTL、费用、耗时、5h / 7d / Fable 限额
- 5h / 7d 限额会缓存到 `~/.claude/statusline-state/rate-limits-cache*.json`（只存百分比和重置时间）：新对话在首次响应前先显示上次的值，重置时间已过的窗口不显示。缓存按 `ANTHROPIC_BASE_URL`、`CLAUDE_CONFIG_DIR` 和是否设置 API Key / Auth Token 分开存放，网关或 API Key 会话不会显示订阅账号的额度；同一配置目录里 `/login` 换号无法识别，删除缓存文件即可清除
- `statusline-fable-refresh.sh`：缓存过期时在后台请求 OAuth Usage API 刷新 Fable 周额度；令牌取自本机钥匙串，只在内存中使用，缓存仅保存百分比

## 同步

```bash
git clone <本仓库> && cd claude-statusline && ./install.sh
```

`install.sh` 只修改 `~/.claude/settings.json` 的 `statusLine` 字段。仓库不包含任何凭据。

## 反向同步（本机改了脚本后）

```bash
./sync.sh "说明"   # 复制 ~/.claude 下的脚本，有变化则提交并推送
```

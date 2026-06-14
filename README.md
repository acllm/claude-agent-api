# Claude Agent API

将 Claude Code Agent 包装为 HTTP API 服务的轻量级应用，可被 n8n 等工作流引擎编排调用。

## 设计原则

- **无状态** — 纯内存，无持久化依赖，Pod 重启不影响
- **零鉴权** — 服务本身不做认证，安全下沉到 K8s NetworkPolicy
- **API Key 从环境变量注入** — 不在每次请求中携带，由 Pod 级别的 `ANTHROPIC_API_KEY` 环境变量决定
- **异步非阻塞** — 提交任务后立即返回 `taskId`，Agent 在后台执行

## API

| 端点 | 方法 | 说明 |
|------|------|------|
| `/healthz` | GET | 健康检查 |
| `/v1/tasks` | POST | 创建异步任务 |
| `/v1/tasks` | GET | 列出所有任务 |
| `/v1/tasks/:id` | GET | 查询任务状态（轮询用） |
| `/v1/tasks/:id/trace` | GET | 获取任务 Trace |
| `/metrics` | GET | Prometheus 指标 |

### 创建任务

```bash
curl -X POST http://localhost:8080/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Say hello in one word",
    "model": "claude-sonnet-4-20250514",
    "maxTurns": 1
  }'
```

```json
{ "taskId": "uuid" }
```

### 轮询结果

```bash
curl http://localhost:8080/v1/tasks/uuid
```

```json
{
  "id": "uuid",
  "status": "completed",
  "result": "Hello.",
  "createdAt": "...",
  "completedAt": "..."
}
```

## 部署

### Helm

```bash
helm upgrade --install claude-agent-api ./chart \
  -n claude-agent --create-namespace \
  --set llm.baseUrl="https://api.anthropic.com/v1" \
  --set llm.apiKey="sk-ant-..." \
  --set llm.models.opus.id="claude-opus-4-20250514"
```

### Docker

```bash
docker build -t claude-agent-api .
docker run -p 8080:8080 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e ANTHROPIC_BASE_URL=https://api.anthropic.com/v1 \
  claude-agent-api
```

## 环境变量

| 变量 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `ANTHROPIC_API_KEY` | 是 | — | Anthropic API Key |
| `ANTHROPIC_BASE_URL` | 否 | `https://api.anthropic.com/v1` | API 端点 |
| `CLAUDE_CODE_MAX_TURNS` | 否 | `10` | 最大执行轮数 |
| `PORT` | 否 | `8080` | 服务端口 |

## 技术栈

- TypeScript + Hono + @anthropic-ai/claude-code SDK
- prom-client (Prometheus 指标)
- 无外部数据库依赖

## License

MIT
import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { task_routes } from './routes/tasks.js';
import { health_routes } from './routes/health.js';
import { init_metrics, metrics_handler } from './services/metrics.js';

const app = new Hono();
const PORT = parseInt(process.env.PORT || '8080', 10);

// 初始化 Metrics
init_metrics();

// === 路由挂载 ===
app.route('/', health_routes);  // /healthz
app.route('/', task_routes);    // /v1/tasks, /v1/tasks/:id, /v1/tasks/:id/trace

// Prometheus Metrics
app.get('/metrics', metrics_handler);

// 启动
console.log(JSON.stringify({
  ts: new Date().toISOString(),
  level: 'info',
  msg: `Claude Agent API starting on port ${PORT}`,
}));

serve({
  fetch: app.fetch,
  port: PORT,
}, (info) => {
  console.log(JSON.stringify({
    ts: new Date().toISOString(),
    level: 'info',
    msg: `Claude Agent API listening on http://0.0.0.0:${info.port}`,
  }));
});
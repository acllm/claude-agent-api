// 健康检查端点

import { Hono } from 'hono';

export const health_routes = new Hono();

// GET /healthz — 健康检查
health_routes.get('/healthz', (c) => {
  return c.json({ status: 'ok' });
});
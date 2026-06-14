// 任务端点 — 创建、查询

import { Hono } from 'hono';
import { execute_task } from '../services/agent-runner.js';
import { get_task, list_tasks, type TaskRequest } from '../services/task-store.js';
import { tasks_created } from '../services/metrics.js';

export const task_routes = new Hono();

// POST /v1/tasks — 创建异步任务
task_routes.post('/v1/tasks', async (c) => {
  let body: TaskRequest;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  if (!body.prompt || typeof body.prompt !== 'string') {
    return c.json({ error: 'prompt is required' }, 400);
  }

  tasks_created.inc();
  const taskId = await execute_task(body);

  return c.json({ taskId }, 201);
});

// GET /v1/tasks — 列出所有任务
task_routes.get('/v1/tasks', (c) => {
  return c.json(list_tasks());
});

// GET /v1/tasks/:id — 查询任务状态
task_routes.get('/v1/tasks/:id', (c) => {
  const task = get_task(c.req.param('id'));
  if (!task) {
    return c.json({ error: 'Task not found' }, 404);
  }
  return c.json({
    id: task.id,
    status: task.status,
    request: {
      prompt: task.request.prompt.slice(0, 500),
      model: task.request.model,
      maxTurns: task.request.maxTurns,
    },
    result: task.result,
    error: task.error,
    createdAt: task.createdAt,
    startedAt: task.startedAt,
    completedAt: task.completedAt,
  });
});

// GET /v1/tasks/:id/trace — 获取任务 Trace
task_routes.get('/v1/tasks/:id/trace', (c) => {
  const task = get_task(c.req.param('id'));
  if (!task) {
    return c.json({ error: 'Task not found' }, 404);
  }
  return c.json({
    taskId: task.id,
    traceCount: task.trace.length,
    trace: task.trace,
  });
});
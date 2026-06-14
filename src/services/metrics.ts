// Prometheus Metrics 采集

import { Registry, Counter, Histogram, Gauge, collectDefaultMetrics } from 'prom-client';

export const registry = new Registry();

export function init_metrics(): void {
  collectDefaultMetrics({ register: registry });
}

// === 业务指标 ===

export const tasks_created = new Counter({
  name: 'claude_agent_tasks_created_total',
  help: 'Total number of tasks created',
  registers: [registry],
});

export const tasks_completed = new Counter({
  name: 'claude_agent_tasks_completed_total',
  help: 'Total number of tasks completed',
  labelNames: ['status'],
  registers: [registry],
});

export const task_duration_seconds = new Histogram({
  name: 'claude_agent_task_duration_seconds',
  help: 'Task execution duration in seconds',
  buckets: [5, 15, 30, 60, 120, 300, 600],
  registers: [registry],
});

export const active_tasks = new Gauge({
  name: 'claude_agent_active_tasks',
  help: 'Number of currently running tasks',
  registers: [registry],
});

export const tool_calls = new Counter({
  name: 'claude_agent_tool_calls_total',
  help: 'Total number of tool calls made by agents',
  labelNames: ['tool'],
  registers: [registry],
});

// Metrics HTTP handler
export async function metrics_handler(c: any): Promise<Response> {
  const metrics = await registry.metrics();
  return new Response(metrics, {
    headers: { 'Content-Type': registry.contentType },
  });
}
// 任务管理 — 纯内存，无状态

import { randomUUID } from 'node:crypto';

export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed';

export interface TaskRequest {
  prompt: string;
  model?: string;
  maxTurns?: number;
  maxBudgetUsd?: number;
  effortLevel?: string;
  allowedTools?: string[];
  workingDir?: string;
  callbackUrl?: string;
}

export interface TaskTrace {
  type: string;
  timestamp: string;
  data: any;
}

export interface Task {
  id: string;
  status: TaskStatus;
  request: TaskRequest;
  result?: string;
  error?: string;
  createdAt: string;
  startedAt?: string;
  completedAt?: string;
  trace: TaskTrace[];
}

// 纯内存存储
const tasks = new Map<string, Task>();

export function create_task(request: TaskRequest): Task {
  const id = randomUUID();
  const task: Task = {
    id,
    status: 'pending',
    request,
    createdAt: new Date().toISOString(),
    trace: [],
  };
  tasks.set(id, task);
  return task;
}

export function get_task(id: string): Task | undefined {
  return tasks.get(id);
}

export function update_task_status(id: string, status: TaskStatus, extra?: Partial<Pick<Task, 'result' | 'error'>>): void {
  const task = tasks.get(id);
  if (!task) return;

  task.status = status;
  if (status === 'running') task.startedAt = new Date().toISOString();
  if (status === 'completed' || status === 'failed') task.completedAt = new Date().toISOString();
  if (extra?.result !== undefined) task.result = extra.result;
  if (extra?.error !== undefined) task.error = extra.error;
}

export function add_trace(id: string, type: string, data: any): void {
  const task = tasks.get(id);
  if (!task) return;

  task.trace.push({
    type,
    timestamp: new Date().toISOString(),
    data,
  });
}

export function list_tasks(): Pick<Task, 'id' | 'status' | 'createdAt' | 'completedAt'>[] {
  return Array.from(tasks.values()).map(t => ({
    id: t.id,
    status: t.status,
    createdAt: t.createdAt,
    completedAt: t.completedAt,
  }));
}

export function count_tasks(): number {
  return tasks.size;
}

export function tasks_by_status(): Record<string, number> {
  const result: Record<string, number> = {};
  for (const t of tasks.values()) {
    result[t.status] = (result[t.status] || 0) + 1;
  }
  return result;
}
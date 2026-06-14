// Claude Code Agent 执行器

import { create_task, update_task_status, add_trace, type TaskRequest } from './task-store.js';
import {
  tasks_completed,
  task_duration_seconds,
  active_tasks,
  tool_calls,
} from './metrics.js';
import type {
  SDKMessage,
  SDKAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  SDKPartialAssistantMessage,
  SDKCompactBoundaryMessage,
} from '@anthropic-ai/claude-code';

export async function execute_task(request: TaskRequest): Promise<string> {
  const task = create_task(request);

  // 异步执行，立即返回 taskId
  setImmediate(() => run_agent(task.id, request));

  return task.id;
}

async function run_agent(taskId: string, request: TaskRequest): Promise<void> {
  const startTime = Date.now();
  active_tasks.inc();
  update_task_status(taskId, 'running');
  add_trace(taskId, 'task_start', {
    prompt: request.prompt.slice(0, 500),
    model: request.model,
    maxTurns: request.maxTurns,
  });

  try {
    const { query } = await import('@anthropic-ai/claude-code');

    const maxTurns = request.maxTurns ?? parseInt(process.env.CLAUDE_CODE_MAX_TURNS || '10', 10);
    const workingDir = request.workingDir || '/workspace';

    const queryOpts: any = {
      prompt: request.prompt,
      options: {
        maxTurns,
        cwd: workingDir,
        permissionMode: 'bypassPermissions',
        env: {
          ...process.env,
          ...(request.effortLevel ? { CLAUDE_CODE_EFFORT_LEVEL: request.effortLevel } : {}),
        },
      },
    };

    if (request.model) queryOpts.options.model = request.model;
    if (request.allowedTools) queryOpts.options.allowedTools = request.allowedTools;

    let finalText = '';
    let sdkError = false;
    let sdkErrorReason = '';

    for await (const message of query(queryOpts) as AsyncIterable<SDKMessage>) {
      switch (message.type) {
        case 'assistant': {
          const msg = message as SDKAssistantMessage;
          const contentBlocks = msg.message?.content || [];
          for (const block of contentBlocks) {
            if (block.type === 'text') {
              add_trace(taskId, 'assistant_text', {
                text: (block as any).text?.slice(0, 1000),
              });
            } else if (block.type === 'tool_use') {
              tool_calls.inc({ tool: block.name });
              add_trace(taskId, 'tool_use', {
                tool: block.name,
                input: JSON.stringify(block.input).slice(0, 500),
              });
            }
          }
          break;
        }

        case 'result': {
          const resultMsg = message as SDKResultMessage;
          if (resultMsg.subtype === 'success') {
            finalText = resultMsg.result || '';
          } else {
            sdkError = true;
            sdkErrorReason = resultMsg.subtype;
          }
          add_trace(taskId, 'result', {
            subtype: resultMsg.subtype,
            result: finalText.slice(0, 2000),
            duration_ms: resultMsg.duration_ms,
            num_turns: resultMsg.num_turns,
            total_cost_usd: resultMsg.total_cost_usd,
            is_error: resultMsg.is_error,
          });
          break;
        }

        case 'system': {
          if ((message as any).subtype === 'compact_boundary') {
            const compactMsg = message as unknown as SDKCompactBoundaryMessage;
            add_trace(taskId, 'compact_boundary', {
              trigger: (compactMsg as any).compact_metadata?.trigger,
              pre_tokens: (compactMsg as any).compact_metadata?.pre_tokens,
            });
          } else {
            const sysMsg = message as SDKSystemMessage;
            add_trace(taskId, 'system', {
              subtype: sysMsg.subtype,
              model: sysMsg.model,
              tools: sysMsg.tools?.slice(0, 20),
            });
          }
          break;
        }

        case 'stream_event': {
          const streamMsg = message as SDKPartialAssistantMessage;
          add_trace(taskId, 'stream_event', {
            eventType: streamMsg.event?.type,
          });
          break;
        }

        default:
          add_trace(taskId, 'message', { type: message.type });
      }
    }

    const duration = (Date.now() - startTime) / 1000;
    if (sdkError) {
      update_task_status(taskId, 'failed', { error: sdkErrorReason, result: finalText || undefined });
      task_duration_seconds.observe(duration);
      tasks_completed.inc({ status: 'error' });
      add_trace(taskId, 'task_end', { duration_seconds: duration, sdk_error: sdkErrorReason });
      if (request.callbackUrl) {
        send_callback(request.callbackUrl, taskId, 'failed', finalText || undefined, sdkErrorReason);
      }
    } else {
      update_task_status(taskId, 'completed', { result: finalText });
      task_duration_seconds.observe(duration);
      tasks_completed.inc({ status: 'success' });
      add_trace(taskId, 'task_end', { duration_seconds: duration });
      if (request.callbackUrl) {
        send_callback(request.callbackUrl, taskId, 'completed', finalText);
      }
    }
  } catch (err: any) {
    const duration = (Date.now() - startTime) / 1000;
    const errorMsg = err?.message || String(err);

    update_task_status(taskId, 'failed', { error: errorMsg });
    task_duration_seconds.observe(duration);
    tasks_completed.inc({ status: 'error' });
    add_trace(taskId, 'task_error', { error: errorMsg, duration_seconds: duration });

    if (request.callbackUrl) {
      send_callback(request.callbackUrl, taskId, 'failed', undefined, errorMsg);
    }
  } finally {
    active_tasks.dec();
  }
}

async function send_callback(
  url: string, taskId: string, status: string, result?: string, error?: string,
): Promise<void> {
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ taskId, status, result, error }),
    });
  } catch (err: any) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: 'error',
      msg: 'Callback failed', url, error: err?.message,
    }));
  }
}
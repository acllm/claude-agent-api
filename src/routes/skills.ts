// Skill 端点 — 列出已挂载的 skills

import { Hono } from 'hono';
import { list_skills } from '../services/skill-scanner.js';

export const skill_routes = new Hono();

// GET /v1/skills — 列出所有已挂载的 skills
skill_routes.get('/v1/skills', (c) => {
  return c.json({ skills: list_skills() });
});

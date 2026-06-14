// Skill 扫描器 — 启动时扫描 /workspace/.claude/skills/，解析 frontmatter，缓存结果

import { readdir } from 'node:fs/promises';
import { readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

export interface SkillMeta {
  name: string;
  description: string;
  path: string;
}

const SKILLS_DIR = process.env.SKILLS_DIR || '/workspace/.claude/skills';

let cached: SkillMeta[] = [];

/**
 * 递归扫描 skills 目录，解析每个 .md 文件的 YAML frontmatter，
 * 返回 { name, description, path } 列表并缓存。
 */
export async function scan_skills(): Promise<SkillMeta[]> {
  cached = [];
  try {
    await walk(SKILLS_DIR, SKILLS_DIR);
  } catch (err: any) {
    // 目录不存在是正常情况（未配置 skills）
    if (err?.code !== 'ENOENT') throw err;
  }
  console.log(JSON.stringify({
    ts: new Date().toISOString(),
    level: 'info',
    msg: `Skills scanned: ${cached.length} found in ${SKILLS_DIR}`,
  }));
  return cached;
}

/** 返回缓存的 skill 列表 */
export function list_skills(): SkillMeta[] {
  return cached;
}

async function walk(dir: string, root: string): Promise<void> {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(full, root);
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      const meta = await parse_frontmatter(full);
      if (meta) {
        cached.push({
          name: meta.name || entry.name.replace(/\.md$/, ''),
          description: meta.description || '',
          path: relative(root, full),
        });
      }
    }
  }
}

/**
 * 解析 .md 文件的 YAML frontmatter，提取 name 和 description。
 * frontmatter 格式:
 *   ---
 *   name: sql-query
 *   description: Generate SQL queries
 *   ---
 */
async function parse_frontmatter(filePath: string): Promise<Record<string, string> | null> {
  const content = await readFile(filePath, 'utf-8');
  const match = content.match(/^---\s*\n([\s\S]*?)\n---/);
  if (!match) return null;

  const yaml = match[1];
  const result: Record<string, string> = {};

  for (const line of yaml.split('\n')) {
    const m = line.match(/^(\w[\w-]*)\s*:\s*(.+)$/);
    if (m) {
      result[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
    }
  }

  return result;
}

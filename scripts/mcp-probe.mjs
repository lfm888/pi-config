#!/usr/bin/env node
//
// mcp-probe.mjs — 用 JSON-RPC 探测一个「本地启动」的 MCP 服务器是否可用
//
// 用法:
//   echo '<服务器配置JSON>' | node scripts/mcp-probe.mjs [--name <名>] [--timeout-ms <毫秒>]
//
// 服务器配置 JSON（与 mcp.json.template 里 mcpServers.<名> 同构）:
//   { "command": "npx", "args": ["-y", "pkg@1", ...], "env": { ... } }
//
// 占位符: 支持 {{VAR}} 与 ${VAR}，探测时若环境变量存在则替换（与 pi-mcp-adapter 行为一致），
//         不存在则原样保留 —— 因此带 {{HOME}} 的配置也能安全探测。
//
// 输出: 一行 JSON
//   { "ok": bool, "skipped": bool?, "toolCount": n, "tools": [...],
//     "serverInfo": {...}?, "error": string?, "stderr": string?, "ms": n }
//
import { spawn } from 'node:child_process';

let serverName = 'server';
let timeoutMs = 180000;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--name') serverName = argv[++i];
  else if (argv[i] === '--timeout-ms') timeoutMs = Number(argv[++i]) || 180000;
}

const sub = (s) =>
  String(s)
    .replace(/\{\{([A-Za-z0-9_]+)\}\}/g, (m, k) => process.env[k] ?? m)
    .replace(/\$\{([A-Za-z0-9_]+)\}/g, (m, k) => process.env[k] ?? m);

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => (raw += d));
process.stdin.on('end', () => {
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch {
    finish({ name: serverName, ok: false, error: 'stdin 不是合法 JSON' });
    return;
  }

  if (!cfg.command) {
    finish({ name: serverName, ok: false, skipped: true, error: '无 command（HTTP 服务器，跳过探测）' });
    return;
  }

  const res = { name: serverName, ok: false, toolCount: 0, tools: [], serverInfo: null, error: null, stderr: '', ms: 0 };
  const t0 = Date.now();

  const args = (cfg.args || []).map(sub);
  const env = { ...process.env };
  for (const [k, v] of Object.entries(cfg.env || {})) env[k] = sub(v);

  let p;
  try {
    p = spawn(sub(cfg.command), args, { stdio: ['pipe', 'pipe', 'pipe'], env });
  } catch (e) {
    finish({ ...res, error: 'spawn: ' + e.message });
    return;
  }

  let buf = '';
  const timer = setTimeout(() => finish({ ...res, error: `超时(${timeoutMs}ms)` }), timeoutMs);

  p.on('error', (e) => { clearTimeout(timer); finish({ ...res, error: 'spawn: ' + e.message }); });
  p.stderr.on('data', (d) => { res.stderr = (res.stderr + d.toString()).slice(-600); });

  p.stdout.on('data', (chunk) => {
    buf += chunk.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id === 1 && msg.result) {
        res.serverInfo = msg.result.serverInfo;
        p.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
        p.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }) + '\n');
      }
      if (msg.id === 2 && msg.result) {
        const tools = msg.result.tools || [];
        res.ok = true;
        res.toolCount = tools.length;
        res.tools = tools.map((t) => t.name);
        clearTimeout(timer);
        finish(res);
      }
    }
  });

  function finish(r) {
    if (!r.ms) r.ms = Date.now() - t0;
    try { p?.kill('SIGKILL'); } catch {}
    console.log(JSON.stringify(r));
  }

  p.stdin.write(
    JSON.stringify({
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: {
        protocolVersion: '2024-11-05',
        capabilities: {},
        clientInfo: { name: 'pi-config-probe', version: '1.0' },
      },
    }) + '\n'
  );
});
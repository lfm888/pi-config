#!/usr/bin/env node
/**
 * render-template.mjs — pi-config 模板渲染器（install.sh 与 verify.sh 共用，避免两处实现漂移）
 *
 * 用法:
 *   node scripts/render-template.mjs <模板文件> <输出文件> [--json]
 *
 * 规则:
 *   · 只替换 {{VAR}}（变量名限 [A-Z0-9_]），值取自同名环境变量；
 *     ${VAR} 形式原样保留（由 pi-mcp-adapter 在启动服务器时展开）
 *   · --json：值按 JSON 字符串转义 —— Windows 的 C:\... 反斜杠不转义会写出非法 JSON；
 *             同时在 Windows 上把 Git Bash 的 MSYS 路径（/c/Users/x）转成 C:/Users/x
 *             （Node/pi 的 fs 不认 /c/... 这种路径）
 *   · 渲染后若仍残留 {{...}}（写法不受支持，例如 {{VAR||默认值}}）→ 报错退出 1，
 *     绝不把「字面量占位符」当路径写进本机配置
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

const [tplPath, outPath, ...flags] = process.argv.slice(2);
const jsonMode = flags.includes("--json");

if (!tplPath || !outPath) {
  console.error("用法: node scripts/render-template.mjs <模板文件> <输出文件> [--json]");
  process.exit(2);
}

/** Git Bash 的 MSYS 路径 → Windows 混合路径：/c/Users/x → C:/Users/x */
const msysToWindows = (p) => p.replace(/^\/([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`);

const prepare = (value) => {
  let v = String(value);
  if (jsonMode && process.platform === "win32") v = msysToWindows(v);
  if (jsonMode) v = v.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return v;
};

const src = readFileSync(tplPath, "utf8");
const rendered = src.replace(/\{\{([A-Z0-9_]+)\}\}/g, (whole, key) =>
  Object.prototype.hasOwnProperty.call(process.env, key) ? prepare(process.env[key]) : whole
);

const leftover = rendered.match(/\{\{[^}]*\}\}/g);
if (leftover) {
  console.error(`✗ ${tplPath} 渲染后仍残留占位符（只支持 {{VAR}}，变量名限 [A-Z0-9_]）：`);
  for (const p of [...new Set(leftover)]) console.error(`    ${p}`);
  process.exit(1);
}

mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, rendered);

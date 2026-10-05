#!/usr/bin/env node
// =============================================================
//  OPENAI IMAGES for Claude  (round AL)
//
//  A tiny MCP server: it lets Claude ask OpenAI's image model to paint
//  pictures (the comic MASTERS), and saves them straight into this project.
//  No packages to install - it only needs Node (already on your Deck,
//  because PixelLab uses npx).
//
//  Your API key stays in claude_desktop_config.json (the "env" part).
//  It is never written in this file and never shown in the chat.
//
//  Tools it gives Claude:
//    start_image  - start a picture: a prompt, optional reference pictures
//                   from the project (style / pose), where to save it.
//                   Returns a job id straight away (pictures take ~1 min).
//    check_image  - is the job done? When done, the PNG is already saved.
//
//  Everything is saved inside the project folder only.
// =============================================================
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(process.env.SB_PROJECT || path.join(path.dirname(fileURLToPath(import.meta.url)), "..", ".."));
const KEY = process.env.OPENAI_API_KEY || "";
const MODEL = process.env.OPENAI_IMAGE_MODEL || "gpt-image-1";
const jobs = new Map();
let nextId = 1;

function inside(rel) {
  const p = path.resolve(ROOT, rel);
  if (p !== ROOT && !p.startsWith(ROOT + path.sep)) throw new Error("path must stay inside the project: " + rel);
  return p;
}

async function paint(args) {
  const size = args.size || "1024x1024";
  const quality = args.quality || "high";
  const background = args.background || "auto";
  const refs = args.reference_images || [];
  let res;
  if (refs.length) {
    const form = new FormData();
    form.append("model", MODEL);
    form.append("prompt", args.prompt);
    form.append("size", size);
    form.append("quality", quality);
    form.append("background", background);
    if (args.input_fidelity) form.append("input_fidelity", args.input_fidelity);
    for (const r of refs) {
      const p = inside(r);
      const type = p.toLowerCase().endsWith(".jpg") || p.toLowerCase().endsWith(".jpeg") ? "image/jpeg" : (p.toLowerCase().endsWith(".webp") ? "image/webp" : "image/png");
      form.append("image[]", new Blob([fs.readFileSync(p)], { type }), path.basename(p));
    }
    res = await fetch("https://api.openai.com/v1/images/edits", { method: "POST", headers: { Authorization: "Bearer " + KEY }, body: form });
  } else {
    res = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: { Authorization: "Bearer " + KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ model: MODEL, prompt: args.prompt, size, quality, background, n: 1 }),
    });
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error("OpenAI said " + res.status + ": " + (body.error && body.error.message || JSON.stringify(body)));
  const b64 = body.data && body.data[0] && body.data[0].b64_json;
  if (!b64) throw new Error("no image in the answer");
  const out = inside(args.out_path);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, Buffer.from(b64, "base64"));
  return { saved: path.relative(ROOT, out), bytes: fs.statSync(out).size, model: MODEL, usage: body.usage || null };
}

const TOOLS = [
  {
    name: "start_image",
    description: "Start painting a picture with OpenAI's image model. Saves a PNG inside the Sturmball project at out_path. Returns a job id; poll check_image. Takes ~30-120 s.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "What to paint." },
        out_path: { type: "string", description: "Where to save, relative to the project, e.g. art_source/openai/hero_01.png" },
        reference_images: { type: "array", items: { type: "string" }, description: "Optional pictures in the project (relative paths) to guide style/pose. Uses the edits endpoint." },
        size: { type: "string", enum: ["1024x1024", "1024x1536", "1536x1024", "auto"] },
        quality: { type: "string", enum: ["low", "medium", "high", "auto"] },
        background: { type: "string", enum: ["transparent", "opaque", "auto"] },
        input_fidelity: { type: "string", enum: ["low", "high"], description: "Edits only: high = stick closer to the reference pictures." },
      },
      required: ["prompt", "out_path"],
    },
  },
  {
    name: "check_image",
    description: "Check a job started by start_image. Status is running, done (with the saved path) or failed (with the reason).",
    inputSchema: { type: "object", properties: { job_id: { type: "string" } }, required: ["job_id"] },
  },
];

function call(name, args) {
  if (name === "start_image") {
    if (!KEY) throw new Error("OPENAI_API_KEY is not set in claude_desktop_config.json");
    if (!args.prompt || !args.out_path) throw new Error("prompt and out_path are needed");
    inside(args.out_path);
    const id = "img" + nextId++;
    const job = { status: "running", started: Date.now() };
    jobs.set(id, job);
    paint(args).then((r) => Object.assign(job, { status: "done" }, r)).catch((e) => Object.assign(job, { status: "failed", error: String(e.message || e) }));
    return { job_id: id, status: "running" };
  }
  if (name === "check_image") {
    const job = jobs.get(args.job_id);
    if (!job) throw new Error("no such job (the server may have restarted): " + args.job_id);
    return Object.assign({ job_id: args.job_id, seconds: Math.round((Date.now() - job.started) / 1000) }, job);
  }
  throw new Error("unknown tool " + name);
}

function send(msg) { process.stdout.write(JSON.stringify(msg) + "\n"); }

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id === undefined) continue; // notifications
    const reply = (result) => send({ jsonrpc: "2.0", id: msg.id, result });
    try {
      if (msg.method === "initialize") {
        reply({ protocolVersion: (msg.params && msg.params.protocolVersion) || "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "sturmball-openai-images", version: "1.0.0" } });
      } else if (msg.method === "tools/list") {
        reply({ tools: TOOLS });
      } else if (msg.method === "tools/call") {
        try {
          const r = call(msg.params.name, msg.params.arguments || {});
          reply({ content: [{ type: "text", text: JSON.stringify(r) }] });
        } catch (e) {
          reply({ content: [{ type: "text", text: "Error: " + (e.message || e) }], isError: true });
        }
      } else if (msg.method === "ping") {
        reply({});
      } else {
        send({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "method not found: " + msg.method } });
      }
    } catch (e) {
      send({ jsonrpc: "2.0", id: msg.id, error: { code: -32603, message: String(e.message || e) } });
    }
  }
});

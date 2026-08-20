import { createServer } from "node:http";
import { handleFixRequest } from "./lib/handle-fix.mjs";
import { loadLocalEnv, requireConfig } from "./lib/env.mjs";

loadLocalEnv();
requireConfig();

const port = Number(process.env.PORT || "8787");
const host = "127.0.0.1";

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", `http://${host}:${port}`);
    if (req.method === "GET" && url.pathname === "/health") {
      send(res, 200, { ok: true });
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/fix") {
      const body = await readBody(req);
      const headers = {
        "content-type": req.headers["content-type"] ?? "application/json",
      };
      if (typeof req.headers.authorization === "string") {
        headers.authorization = req.headers.authorization;
      }
      const request = new Request(url, {
        method: "POST",
        headers,
        body,
      });
      const response = await handleFixRequest(request);
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
      return;
    }
    send(res, 404, { error: "not_found" });
  } catch {
    send(res, 500, { error: "server_error" });
  }
});

server.listen(port, host, () => {
  console.log(`fix proxy listening on http://${host}:${port}`);
});

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json" });
  res.end(payload);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

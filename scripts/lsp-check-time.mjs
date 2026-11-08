// Time one `awsum lsp` check: send `textDocument/didOpen` for FILE and wait for
// the `textDocument/publishDiagnostics` the server pushes for it. The
// diagnostics are discarded; only the elapsed time is printed. The server
// checks a didOpen immediately (the 500 ms debounce applies to didChange only),
// so the figure is the check itself, without process startup or the
// initialize handshake.
//
// Usage: node scripts/lsp-check-time.mjs AWSUM_BINARY FILE

import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [binary, file] = process.argv.slice(2);
if (!binary || !file) {
  console.error("usage: node scripts/lsp-check-time.mjs AWSUM_BINARY FILE");
  process.exit(2);
}
const uri = pathToFileURL(resolve(file)).href;
const text = readFileSync(file, "utf8");

const server = spawn(binary, ["lsp", "--stdio"], { stdio: ["pipe", "pipe", "ignore"] });
let done = false;
server.on("exit", (code) => {
  if (!done) {
    console.error(`awsum lsp exited before answering (code ${code})`);
    process.exit(1);
  }
});
const timeout = setTimeout(() => {
  console.error("no diagnostics within 60 s");
  server.kill();
  process.exit(1);
}, 60_000);

function send(message) {
  const body = Buffer.from(JSON.stringify({ jsonrpc: "2.0", ...message }));
  server.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  server.stdin.write(body);
}

// Resolve the first message each pending matcher accepts.
const waiters = [];
const waitFor = (match) => new Promise((res) => waiters.push({ match, res }));

let buffer = Buffer.alloc(0);
server.stdout.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  for (;;) {
    const separator = buffer.indexOf("\r\n\r\n");
    if (separator < 0) return;
    const length = Number(/Content-Length: *(\d+)/i.exec(buffer.subarray(0, separator).toString())[1]);
    const start = separator + 4;
    if (buffer.length < start + length) return;
    const message = JSON.parse(buffer.subarray(start, start + length).toString("utf8"));
    buffer = buffer.subarray(start + length);
    // A request from the server carries both an id and a method; answer it so
    // the server never waits on us.
    if (message.id !== undefined && message.method) send({ id: message.id, result: null });
    const i = waiters.findIndex((w) => w.match(message));
    if (i >= 0) waiters.splice(i, 1)[0].res(message);
  }
});

const sameUri = (a, b) => decodeURIComponent(a) === decodeURIComponent(b);

send({ id: 1, method: "initialize", params: { processId: process.pid, rootUri: null, capabilities: {} } });
await waitFor((m) => m.id === 1 && !m.method);
send({ method: "initialized", params: {} });

const diagnostics = waitFor((m) => m.method === "textDocument/publishDiagnostics" && sameUri(m.params.uri, uri));
const started = process.hrtime.bigint();
send({ method: "textDocument/didOpen", params: { textDocument: { uri, languageId: "awsum", version: 1, text } } });
await diagnostics;
console.log(`${(Number(process.hrtime.bigint() - started) / 1e6).toFixed(1)} ms`);

done = true;
clearTimeout(timeout);
send({ id: 2, method: "shutdown" });
await waitFor((m) => m.id === 2 && !m.method);
send({ method: "exit" });
server.stdin.end();

// Stand-in for YOUR backend: after your own login, it mints a HaloChat client token
// with the channel's server key. The key stays on the server; the app never sees it.
//
//   HALOCHAT_SERVER_KEY=hck_... node server.mjs
//
// A real backend reads the user from its own session, not from a query parameter.
import { createServer } from "node:http";

const KEY = process.env.HALOCHAT_SERVER_KEY;
const BASE = process.env.HALO_BASE_URL ?? "https://www.haloai.co.id";
const PORT = Number(process.env.PORT ?? 8791);
if (!KEY?.startsWith("hck_")) throw new Error("Set HALOCHAT_SERVER_KEY to the channel's server key");

createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname !== "/halochat-token") return res.writeHead(404).end();
  const upstream = await fetch(`${BASE}/api/open/inApp/v1/clientToken`, {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      externalUserId: url.searchParams.get("user") ?? "sample-user-1",
      displayName: "Sample user",
    }),
  });
  const body = await upstream.json().catch(() => null);
  res.writeHead(upstream.ok ? 200 : 502, { "Content-Type": "application/json" });
  res.end(JSON.stringify(upstream.ok ? { token: body.data.token } : { error: "mint_failed", status: upstream.status }));
}).listen(PORT, "127.0.0.1", () => console.log(`sample backend on http://127.0.0.1:${PORT}`));

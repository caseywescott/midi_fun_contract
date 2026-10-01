// Run the Beast Sound endpoint on Node 20+:  node server/node.mjs [port]
import { createServer } from 'node:http';
import { handleRequest } from './handler.js';

const port = Number(process.argv[2] || process.env.PORT || 8787);
createServer(async (req, res) => {
  const response = await handleRequest(new Request(`http://${req.headers.host}${req.url}`, { method: req.method }));
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(port, () => console.log(`Beast Sound on http://localhost:${port}/beasts/52918.json`));

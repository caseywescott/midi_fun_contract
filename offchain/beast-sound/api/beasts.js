// Vercel function: forwards every /beasts/... request to the shared Fetch-standard handler.
import { handleRequest } from '../server/handler.js';

// vercel.json rewrites /beasts/{rest} to /api/beasts?__path={rest}; restore the public path so the
// handler's routing and generated links match what the caller requested.
function publicRequest(request) {
  const url = new URL(request.url);
  if (!url.searchParams.has('__path')) return request;
  const rest = url.searchParams.get('__path');
  url.searchParams.delete('__path');
  url.pathname = rest ? `/beasts/${rest}` : '/';
  return new Request(url, request);
}

export async function GET(request) {
  return handleRequest(publicRequest(request));
}

export async function OPTIONS(request) {
  return handleRequest(publicRequest(request));
}

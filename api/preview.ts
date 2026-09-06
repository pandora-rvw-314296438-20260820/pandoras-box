const TOKEN_RE = /^[0-9a-f]{64}$/;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const UPSTREAM_ORIGIN =
  'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-preview-host';

export const config = { maxDuration: 10 };

function queryValue(value: unknown): string {
  if (Array.isArray(value)) return String(value[0] ?? '').trim();
  return typeof value === 'string' ? value.trim() : '';
}

function safePath(value: string): string | null {
  const path = value || 'index.html';
  if (
    !path ||
    path.length > 512 ||
    path.startsWith('/') ||
    path.endsWith('/') ||
    path.includes('\\') ||
    path.includes('\0') ||
    path.includes('?') ||
    path.includes('#')
  ) {
    return null;
  }
  const parts = path.split('/');
  if (
    parts.some(
      (part) =>
        !part ||
        part === '.' ||
        part === '..' ||
        part.length > 255,
    )
  ) {
    return null;
  }
  return parts.map((part) => encodeURIComponent(part)).join('/');
}

function contentType(path: string): string {
  const extension = path.toLowerCase().split('.').pop() ?? '';
  const types: Record<string, string> = {
    html: 'text/html; charset=utf-8',
    htm: 'text/html; charset=utf-8',
    css: 'text/css; charset=utf-8',
    js: 'text/javascript; charset=utf-8',
    mjs: 'text/javascript; charset=utf-8',
    json: 'application/json; charset=utf-8',
    map: 'application/json; charset=utf-8',
    txt: 'text/plain; charset=utf-8',
    xml: 'application/xml; charset=utf-8',
    svg: 'image/svg+xml',
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    gif: 'image/gif',
    webp: 'image/webp',
    ico: 'image/x-icon',
    woff: 'font/woff',
    woff2: 'font/woff2',
    ttf: 'font/ttf',
    otf: 'font/otf',
    wasm: 'application/wasm',
    pdf: 'application/pdf',
  };
  return types[extension] ?? 'application/octet-stream';
}

function setPreviewHeaders(response: any, path: string) {
  response.setHeader('Cache-Control', 'private, no-store, max-age=0');
  response.setHeader('CDN-Cache-Control', 'no-store');
  response.setHeader('Content-Type', contentType(path));
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('Referrer-Policy', 'no-referrer');
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  response.setHeader(
    'Permissions-Policy',
    'camera=(), geolocation=(), microphone=(), payment=(), usb=()',
  );
  response.setHeader(
    'Content-Security-Policy',
    [
      "default-src 'none'",
      "script-src 'unsafe-inline' 'unsafe-eval' https:",
      "style-src 'unsafe-inline' https:",
      'img-src data: blob: https:',
      'font-src data: https:',
      'media-src data: blob: https:',
      'connect-src https: wss:',
      'worker-src blob:',
      'child-src blob: https:',
      'frame-src https:',
      "object-src 'none'",
      "base-uri 'none'",
      "form-action 'none'",
      'sandbox allow-scripts allow-popups allow-modals allow-downloads',
    ].join('; '),
  );
}

export default async function preview(request: any, response: any) {
  const method = String(request.method ?? 'GET').toUpperCase();
  if (method !== 'GET' && method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD');
    response.status(405).send('Method not allowed');
    return;
  }

  const token = queryValue(request.query?.token).toLowerCase();
  const rawPath = queryValue(request.query?.path) || 'index.html';
  const path = safePath(rawPath);
  if (!TOKEN_RE.test(token) || path == null) {
    response.status(404).send('Not found');
    return;
  }

  const upstreamUrl = `${UPSTREAM_ORIGIN}/${token}/${path}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const upstream = await fetch(upstreamUrl, {
      method,
      headers: {
        accept: '*/*',
        'cache-control': 'no-store',
        'user-agent': 'Pandora-Renderable-Preview/1.0',
      },
      redirect: 'error',
      signal: controller.signal,
    });

    if (!upstream.ok) {
      const status = [404, 410, 503].includes(upstream.status)
        ? upstream.status
        : 502;
      response.status(status).send(
        status === 410 ? 'Preview expired' : 'Preview unavailable',
      );
      return;
    }

    setPreviewHeaders(response, rawPath);
    const declaredLength = Number(upstream.headers.get('content-length') ?? '0');
    if (
      Number.isFinite(declaredLength) &&
      declaredLength > MAX_FILE_BYTES
    ) {
      response.status(502).send('Preview unavailable');
      return;
    }

    if (method === 'HEAD') {
      if (declaredLength > 0) {
        response.setHeader('Content-Length', String(declaredLength));
      }
      response.status(200).end();
      return;
    }

    const bytes = Buffer.from(await upstream.arrayBuffer());
    if (bytes.length < 1 || bytes.length > MAX_FILE_BYTES) {
      response.status(502).send('Preview unavailable');
      return;
    }
    response.setHeader('Content-Length', String(bytes.length));
    response.status(200).send(bytes);
  } catch {
    response.status(503).send('Preview unavailable');
  } finally {
    clearTimeout(timeout);
  }
}

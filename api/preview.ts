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


function injectFocusBridge(html: string): string {
  const bridge = `<style id="pandora-focus-bridge-style">
[data-pandora-focus-hover="true"]{outline:2px solid rgba(220,48,48,.95)!important;outline-offset:2px!important;cursor:crosshair!important}
</style><script id="pandora-focus-bridge-script">
(()=>{let enabled=false;let hover=null;
const clean=(value,max)=>String(value||'').replace(/\\s+/g,' ').trim().slice(0,max);
const label=(el)=>clean(el.getAttribute('aria-label')||el.getAttribute('alt')||el.getAttribute('title')||el.textContent||'',300);
const role=(el)=>el.getAttribute('role')||({A:'link',BUTTON:'button',INPUT:'input',TEXTAREA:'textbox',SELECT:'combobox',IMG:'img',H1:'heading',H2:'heading',H3:'heading',H4:'heading',H5:'heading',H6:'heading'}[el.tagName]||'');
const selector=(el)=>{const parts=[];let node=el;for(let depth=0;node&&node.nodeType===1&&depth<5;depth+=1,node=node.parentElement){let part=node.tagName.toLowerCase();const siblings=node.parentElement?[...node.parentElement.children].filter((item)=>item.tagName===node.tagName):[];if(siblings.length>1)part+=':nth-of-type('+(siblings.indexOf(node)+1)+')';parts.unshift(part);}return parts.join(' > ');};
const clear=()=>{if(hover)hover.removeAttribute('data-pandora-focus-hover');hover=null;};
const choose=(el)=>{const rect=el.getBoundingClientRect();const sel=selector(el);const name=label(el);const r=role(el);const semantic=clean(el.getAttribute('data-pandora-semantic-id')||el.getAttribute('data-pandora-component-id')||el.id||(r&&name?r+':'+name.slice(0,120):sel),400);const component=clean(el.getAttribute('data-pandora-component-id')||el.id||semantic,200);const sourceLine=Number(el.getAttribute('data-pandora-source-line')||0);return{type:'pandora.preview.selection.v2',componentId:component,semanticId:semantic,selector:sel,role:r,accessibleName:name,route:location.pathname+location.hash,sourceFile:clean(el.getAttribute('data-pandora-source-file')||'index.html',512),sourceLine:Number.isSafeInteger(sourceLine)&&sourceLine>0?sourceLine:null,bounds:{x:Math.max(0,rect.x),y:Math.max(0,rect.y),width:Math.max(0,rect.width),height:Math.max(0,rect.height)}};};
addEventListener('message',(event)=>{if(event.source!==parent)return;const data=event.data||{};if(data.type!=='pandora.preview.focus-mode.v1')return;enabled=data.enabled===true;clear();});
addEventListener('pointerover',(event)=>{if(!enabled)return;const el=event.target instanceof Element?event.target:null;if(!el)return;clear();hover=el;hover.setAttribute('data-pandora-focus-hover','true');},true);
addEventListener('pointerout',(event)=>{if(!enabled)return;const next=event.relatedTarget;if(hover&&next instanceof Node&&hover.contains(next))return;clear();},true);
addEventListener('click',(event)=>{if(!enabled)return;const el=event.target instanceof Element?event.target:null;if(!el)return;event.preventDefault();event.stopImmediatePropagation();const payload=choose(el);enabled=false;clear();parent.postMessage(payload,'*');},true);
})();</script>`;
  if (/<\/body\s*>/i.test(html)) return html.replace(/<\/body\s*>/i, `${bridge}</body>`);
  return `${html}${bridge}`;
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
  const focusMode = queryValue(request.query?.focus) === '1';
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
    let output = bytes;
    if (focusMode && /\.html?$/i.test(rawPath)) {
      try {
        const html = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
        output = Buffer.from(injectFocusBridge(html), 'utf8');
      } catch {
        response.status(502).send('Preview unavailable');
        return;
      }
      if (output.length > MAX_FILE_BYTES) {
        response.status(502).send('Preview unavailable');
        return;
      }
    }
    response.setHeader('Content-Length', String(output.length));
    response.status(200).send(output);
  } catch {
    response.status(503).send('Preview unavailable');
  } finally {
    clearTimeout(timeout);
  }
}

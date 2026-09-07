if (typeof window !== 'undefined' && typeof document !== 'undefined') {
const { state } = window.PandorasOwnerData;
const decoder = new TextDecoder('utf-8', { fatal: true });
let mountedFrame = null;
let privilegedPort = null;

function workspace() { return state.projectWorkspace; }

function bytes(value) {
  const binary = atob(String(value || ''));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out;
}

function uri(mime, value) {
  let binary = '';
  const chunk = 0x8000;
  for (let offset = 0; offset < value.length; offset += chunk) {
    binary += String.fromCharCode(...value.subarray(offset, Math.min(offset + chunk, value.length)));
  }
  return `data:${mime};base64,${btoa(binary)}`;
}

function resolvePath(basePath, rawRef, files) {
  const ref = String(rawRef || '').trim();
  if (!ref || ref.startsWith('#') || /^(?:data:|blob:|javascript:|mailto:|tel:|\/\/|[a-zA-Z][a-zA-Z0-9+.-]*:)/.test(ref)) return null;
  const clean = ref.split('#')[0].split('?')[0];
  const parts = [];
  if (!clean.startsWith('/')) {
    const base = basePath.split('/');
    base.pop();
    parts.push(...base);
  }
  for (const segment of clean.split('/')) {
    if (!segment || segment === '.') continue;
    if (segment === '..') {
      if (!parts.length) return null;
      parts.pop();
    } else {
      parts.push(segment);
    }
  }
  const path = parts.join('/');
  return files.has(path) ? path : null;
}

function rawUri(file) {
  return uri(file.mimeType, file.bytes);
}

function materialize(path, files, cache, visiting) {
  if (cache.has(path)) return cache.get(path);
  const file = files.get(path);
  if (!file) return '';
  if (visiting.has(path)) return rawUri(file);
  visiting.add(path);
  let body = file.bytes;
  const mime = file.mimeType.toLowerCase();

  if (mime.includes('css') || mime.includes('javascript') || mime.endsWith('/json') || mime.startsWith('text/')) {
    try {
      let source = decoder.decode(body);
      if (mime.includes('css')) {
        source = source.replace(/url\(\s*(['"]?)([^)'"]+)\1\s*\)/gi, (match, quote, ref) => {
          const nested = resolvePath(path, ref, files);
          return nested ? `url("${materialize(nested, files, cache, visiting)}")` : match;
        });
      } else if (mime.includes('javascript')) {
        const rewrite = (match, before, ref, after) => {
          const nested = resolvePath(path, ref, files);
          return nested ? `${before}${materialize(nested, files, cache, visiting)}${after}` : match;
        };
        source = source
          .replace(/(\bfrom\s*['"])([^'"]+)(['"])/g, rewrite)
          .replace(/(\bimport\s*['"])([^'"]+)(['"])/g, rewrite)
          .replace(/(\bimport\s*\(\s*['"])([^'"]+)(['"]\s*\))/g, rewrite);
      }
      body = new TextEncoder().encode(source);
    } catch {
      visiting.delete(path);
      return rawUri(file);
    }
  }

  const result = uri(file.mimeType, body);
  cache.set(path, result);
  visiting.delete(path);
  return result;
}

function scriptJson(value) {
  return JSON.stringify(value).replaceAll('<', '\\u003c').replaceAll('>', '\\u003e').replaceAll('&', '\\u0026');
}

function bootstrap(versionId) {
  return `(() => {
    'use strict';
    const expectedVersionId=${scriptJson(versionId)};
    let port=null;
    let selectionEnabled=false;
    let selectedSelector='';
    const clear=()=>document.querySelectorAll('[data-pandora-preview-selected="true"]').forEach(node=>node.removeAttribute('data-pandora-preview-selected'));
    const ensureStyle=()=>{if(document.getElementById('pandora-preview-selection-style'))return;const s=document.createElement('style');s.id='pandora-preview-selection-style';s.textContent='[data-pandora-preview-selected="true"]{outline:2px solid rgba(25,25,25,.78)!important;outline-offset:2px!important;cursor:crosshair!important}';document.head.appendChild(s);};
    const cssEscape=value=>(window.CSS&&CSS.escape)?CSS.escape(value):String(value).replace(/[^a-zA-Z0-9_-]/g,ch=>'\\\\'+ch);
    const selectorFor=node=>{const semantic=node.getAttribute('data-pandora-id');if(semantic)return '[data-pandora-id="'+cssEscape(semantic)+'"]';if(node.id)return '#'+cssEscape(node.id);const parts=[];let current=node;while(current&&current.nodeType===1&&current!==document.documentElement){let part=current.tagName.toLowerCase();const parent=current.parentElement;if(parent){const peers=Array.from(parent.children).filter(child=>child.tagName===current.tagName);if(peers.length>1)part+=':nth-of-type('+(peers.indexOf(current)+1)+')';}parts.unshift(part);current=parent;if(parts.length>=8)break;}return parts.join(' > ');};
    const apply=()=>{clear();if(!selectedSelector)return;try{const node=document.querySelector(selectedSelector);if(node){ensureStyle();node.setAttribute('data-pandora-preview-selected','true');}}catch{}};

    window.addEventListener('message',event=>{
      if(!event.isTrusted||event.ports.length!==1||port!==null)return;
      const message=event.data;
      if(!message||message.type!=='pandora-preview-init'||message.versionId!==expectedVersionId)return;
      event.stopImmediatePropagation();
      port=event.ports[0];
      port.onmessage=portEvent=>{
        if(typeof portEvent.data!=='string')return;
        let command;
        try{command=JSON.parse(portEvent.data)}catch{return}
        if(!command||command.type!=='state'||command.versionId!==expectedVersionId)return;
        selectionEnabled=command.selectionEnabled===true;
        selectedSelector=typeof command.selectedSelector==='string'?command.selectedSelector:'';
        apply();
      };
      port.postMessage(JSON.stringify({type:'ready',versionId:expectedVersionId}));
    },true);

    document.addEventListener('click',event=>{
      const anchor=event.target&&event.target.closest?event.target.closest('a[href]'):null;
      if(anchor){
        const href=String(anchor.getAttribute('href')||'').trim();
        if(/^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|\\/\\/)/.test(href)&&!href.startsWith('data:')&&!href.startsWith('blob:')){
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
      }
      if(!selectionEnabled||!port)return;
      const element=document.elementFromPoint(event.clientX,event.clientY);
      if(!element||element===document.documentElement||element===document.body)return;
      event.preventDefault();
      event.stopImmediatePropagation();
      clear();
      ensureStyle();
      element.setAttribute('data-pandora-preview-selected','true');
      selectedSelector=selectorFor(element);
      const rect=element.getBoundingClientRect();
      const lineRaw=element.getAttribute('data-pandora-source-line');
      const sourceLine=lineRaw&&/^\\d+$/.test(lineRaw)?Number(lineRaw):null;
      port.postMessage(JSON.stringify({
        type:'selection',
        versionId:expectedVersionId,
        tag:element.tagName?element.tagName.toLowerCase():'',
        selector:selectedSelector,
        text:String(element.textContent||'').trim().slice(0,500),
        componentId:String(element.getAttribute('data-pandora-component-id')||element.getAttribute('data-component-id')||element.getAttribute('data-pandora-id')||element.id||selectedSelector).trim().slice(0,200),
        semanticId:String(element.getAttribute('data-pandora-id')||''),
        role:String(element.getAttribute('role')||''),
        accessibleName:String(element.getAttribute('aria-label')||element.getAttribute('title')||''),
        route:location.hash&&location.hash.startsWith('#/')?location.hash.substring(1):'/',
        sourceFile:String(element.getAttribute('data-pandora-source-file')||'index.html'),
        sourceLine,
        x:rect.x,y:rect.y,width:rect.width,height:rect.height
      }));
    },true);
  })();`;
}

function documentFor(bundle) {
  const files = new Map();
  for (const entry of Array.isArray(bundle?.files) ? bundle.files : []) {
    const path = String(entry?.file || '');
    if (!path || typeof entry?.dataBase64 !== 'string') continue;
    files.set(path, {
      mimeType: String(entry?.mimeType || 'application/octet-stream'),
      bytes: bytes(entry.dataBase64),
    });
  }
  const index = files.get('index.html');
  if (!index) throw new Error('Pandora preview entrypoint is unavailable');
  let html = decoder.decode(index.bytes);
  const cache = new Map();
  html = html.replace(/(\b(?:src|href|poster)\s*=\s*['"])([^'"]+)(['"])/gi, (match, before, ref, after) => {
    const nested = resolvePath('index.html', ref, files);
    return nested ? `${before}${materialize(nested, files, cache, new Set())}${after}` : match;
  });

  const hosted = bundle?.sourceIncluded === false;
  const csp = hosted
    ? "default-src 'none'; script-src 'unsafe-inline' https: data: blob:; style-src 'unsafe-inline' https: data: blob:; img-src https: data: blob:; font-src https: data: blob:; media-src https: data: blob:; connect-src 'none'; frame-src 'none'; child-src 'none'; object-src 'none'; form-action 'none'; base-uri https:"
    : "default-src 'none'; script-src 'unsafe-inline' data: blob:; style-src 'unsafe-inline' data: blob:; img-src data: blob:; font-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; child-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'";
  const security = `<meta http-equiv="Content-Security-Policy" content="${csp.replaceAll('"','&quot;')}"><meta name="referrer" content="no-referrer"><script>${bootstrap(bundle.versionId)}<\/script>`;
  const match = /<head\b[^>]*>/i.exec(html);
  if (match) return html.slice(0, match.index + match[0].length) + security + html.slice(match.index + match[0].length);
  return '<!doctype html><html><head>' + security + '</head><body>' + html + '</body></html>';
}

function createFocusToken(selection) {
  const item = workspace();
  const projectId = String(item.runtime?.project?.id || '').trim().toLowerCase();
  const versionId = String(item.previewVersionId || '').trim().toLowerCase();
  const artifactDigest = String(item.previewArtifactDigest || '').trim().toLowerCase();
  const componentId = String(selection.componentId || selection.semanticId || selection.selector || '').trim().slice(0, 200);
  const semanticId = String(selection.semanticId || selection.selector || '').trim();
  const sourceFile = String(selection.sourceFile || 'index.html').trim();
  if (!projectId || !versionId || !/^[0-9a-f]{64}$/.test(artifactDigest) || !componentId || !semanticId || sourceFile.startsWith('/') || sourceFile.includes('..') || sourceFile.includes('\\')) {
    throw new Error('Pandora could not bind that object to the exact preview');
  }
  const issuedAt = new Date();
  const expiresAt = new Date(issuedAt.getTime() + 15 * 60 * 1000);
  return {
    schemaVersion: 2,
    projectId, versionId, artifactDigest, componentId, semanticId,
    selector: String(selection.selector || '').trim(),
    role: String(selection.role || '').trim(),
    accessibleName: String(selection.accessibleName || '').trim(),
    route: String(selection.route || '/').trim() || '/',
    sourceFile,
    sourceLine: Number.isInteger(selection.sourceLine) && selection.sourceLine > 0 ? selection.sourceLine : null,
    bounds: { x: Number(selection.x)||0, y: Number(selection.y)||0, width: Number(selection.width)||0, height: Number(selection.height)||0 },
    issuedAt: issuedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
  };
}

function matchesVisible(token) {
  const item = workspace();
  return token?.schemaVersion === 2
    && Date.parse(token.expiresAt || '') > Date.now()
    && token.projectId === String(item.runtime?.project?.id || '').trim().toLowerCase()
    && token.versionId === String(item.previewVersionId || '').trim().toLowerCase()
    && token.artifactDigest === String(item.previewArtifactDigest || '').trim().toLowerCase();
}

function intentContext(token) {
  if (!matchesVisible(token)) {
    throw new Error('That selection belongs to an older preview. Select the object again before changing it.');
  }
  const parts = [
    'FocusToken(v2)',
    `project=${token.projectId}`,
    `version=${token.versionId}`,
    `artifact_sha256=${token.artifactDigest}`,
    `component_id=${token.componentId}`,
    `semantic_id=${token.semanticId}`,
    `source=${token.sourceFile}${token.sourceLine ? ':' + token.sourceLine : ''}`,
    `route=${token.route}`,
    `issued_at=${token.issuedAt}`,
    `expires_at=${token.expiresAt}`,
  ];
  if (token.role) parts.push(`role=${token.role}`);
  if (token.accessibleName) parts.push(`name=${token.accessibleName}`);
  if (token.selector) parts.push(`selector=${token.selector}`);
  if (token.bounds) {
    parts.push(`bounds=x=${token.bounds.x.toFixed(1)},y=${token.bounds.y.toFixed(1)},w=${token.bounds.width.toFixed(1)},h=${token.bounds.height.toFixed(1)}`);
  }
  return parts.join(' ') + '. Apply the owner change specifically to this exact selected object.';
}

function clear() {
  const item = workspace();
  item.selectionMode = false;
  item.previewSelection = null;
  item.focusToken = null;
  if (privilegedPort && item.previewVersionId) {
    privilegedPort.postMessage(JSON.stringify({
      type: 'state',
      versionId: item.previewVersionId,
      selectionEnabled: false,
      selectedSelector: '',
    }));
  }
}

function mount() {
  privilegedPort?.close?.();
  privilegedPort = null;
  mountedFrame = null;
  const item = workspace();
  const host = document.querySelector('[data-owner-preview-host]');
  if (!host || !item.previewBundle || !item.previewVersionId || item.previewBundle.versionId !== item.previewVersionId) return;

  const frame = document.createElement('iframe');
  frame.className = 'owner-preview-frame';
  frame.title = 'Exact Pandora project preview';
  frame.setAttribute('sandbox', 'allow-scripts');
  frame.setAttribute('referrerpolicy', 'no-referrer');
  frame.srcdoc = documentFor(item.previewBundle);
  frame.addEventListener('load', () => {
    if (frame !== mountedFrame) return;
    const channel = new MessageChannel();
    privilegedPort = channel.port1;
    channel.port1.onmessage = (event) => {
      if (typeof event.data !== 'string') return;
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (!message || message.versionId !== item.previewVersionId) return;
      if (message.type === 'ready') {
        channel.port1.postMessage(JSON.stringify({
          type: 'state',
          versionId: item.previewVersionId,
          selectionEnabled: item.selectionMode === true,
          selectedSelector: item.focusToken?.selector || '',
        }));
        return;
      }
      if (message.type !== 'selection') return;
      try {
        item.previewSelection = message;
        item.focusToken = createFocusToken(message);
        item.selectionMode = false;
        item.error = null;
        window.PandorasOwnerRender?.();
      } catch (error) {
        clear();
        item.error = error?.message || 'Pandora could not identify that object safely.';
        window.PandorasOwnerRender?.();
      }
    };
    frame.contentWindow?.postMessage(
      { type: 'pandora-preview-init', versionId: item.previewVersionId },
      '*',
      [channel.port2],
    );
  }, { once: true });

  host.replaceChildren(frame);
  mountedFrame = frame;
}

window.PandorasOwnerPreviewFocus = Object.freeze({
  mount,
  clear,
  matchesVisible,
  intentContext,
});
}

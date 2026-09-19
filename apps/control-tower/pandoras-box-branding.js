const CANONICAL_NAME = "Pandoras-Box";
const LEGACY_DISPLAY_NAME = "Pandora";
const TECHNICAL_NAMESPACE = "pandora";

function replaceDisplayName(value) {
  return typeof value === "string"
    ? value.replaceAll(LEGACY_DISPLAY_NAME, CANONICAL_NAME)
    : value;
}

function shouldSkip(node) {
  const parent = node.parentElement;
  return Boolean(parent?.closest("script, style, code, pre, textarea"));
}

function updateTextNode(node) {
  if (shouldSkip(node)) return;
  const next = replaceDisplayName(node.nodeValue);
  if (next !== node.nodeValue) node.nodeValue = next;
}

function updateElement(element) {
  for (const attribute of ["aria-label", "title", "placeholder", "alt"]) {
    if (!element.hasAttribute(attribute)) continue;
    const current = element.getAttribute(attribute);
    const next = replaceDisplayName(current);
    if (next !== current) element.setAttribute(attribute, next);
  }

  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  let node = walker.nextNode();
  while (node) {
    updateTextNode(node);
    node = walker.nextNode();
  }
}

function applyCanonicalBranding() {
  document.title = replaceDisplayName(document.title);
  const description = document.querySelector('meta[name="description"]');
  if (description) {
    description.setAttribute("content", replaceDisplayName(description.getAttribute("content")));
  }
  if (document.body) updateElement(document.body);
}

Object.defineProperty(window, "PANDORAS_BOX", {
  configurable: false,
  enumerable: true,
  writable: false,
  value: Object.freeze({
    canonicalName: CANONICAL_NAME,
    legacyDisplayName: LEGACY_DISPLAY_NAME,
    technicalNamespace: TECHNICAL_NAMESPACE,
  }),
});

const observer = new MutationObserver((mutations) => {
  for (const mutation of mutations) {
    if (mutation.type === "characterData") {
      updateTextNode(mutation.target);
      continue;
    }
    for (const node of mutation.addedNodes) {
      if (node.nodeType === Node.TEXT_NODE) updateTextNode(node);
      if (node.nodeType === Node.ELEMENT_NODE) updateElement(node);
    }
  }
});

applyCanonicalBranding();
observer.observe(document.documentElement, {
  childList: true,
  subtree: true,
  characterData: true,
});

window.dispatchEvent(new CustomEvent("pandoras-box:branding-ready", {
  detail: { canonicalName: CANONICAL_NAME, technicalNamespace: TECHNICAL_NAMESPACE },
}));

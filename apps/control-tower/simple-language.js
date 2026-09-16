const SIMPLE_TASKS = {
  "PO-010": "Have a different AI check this exact version",
  "PO-011": "Check whether Copilot can build work by itself",
  "PO-012": "Check whether Gemini can work without a computer",
  "PO-013": "Confirm what Jules already completed for CallGate",
  "PO-014": "Complete the first automatic CallGate task",
  "PO-015": "Prove ProjectOS can fix CallGate failures",
  "PO-016": "Prove ProjectOS can watch and safely restore a CallGate release",
  "PO-017": "Save live ProjectOS memory in Supabase",
  "PO-018": "Recover the same status after a session ends",
  "PO-019": "Finish smart routing, permissions, and monitoring",
  "PO-020": "Use ProjectOS across all Banatao Systems products",
};

const SIMPLE_PHASES = {
  "Safe native agent mesh": "Safety foundation",
  "Thin GitHub dispatcher": "Automatic work routing",
  "CallGate production proof": "Prove it on CallGate",
  "Durable ProjectOS state": "Save ProjectOS memory",
  "Deterministic scale and operations": "Smarter routing and monitoring",
  "Portfolio substrate": "Use it across all products",
};

const ROUTE_SUBTITLES = {
  ProjectOS: "Your projects, current work, and next step",
  "Manual Actions": "Use only when ProjectOS needs a manual action",
  "Action Builder": "Set up one exact manual action",
  Plans: "Saved work and its current status",
  "Approval Center": "Important actions waiting for your decision",
  Connections: "Connected services ProjectOS can use",
  "Audit Trail": "Complete history and saved proof",
  "Security Center": "Safety rules and protection status",
  Operations: "System status, releases, and recovery",
  Settings: "Display and connection settings",
  More: "More ProjectOS controls",
};

const SIMPLE_PAGE_TITLES = {
  "Manual Actions": "Manual action",
  "Action Builder": "Manual action",
  Plans: "Saved work",
  "Approval Center": "Approvals",
  "Audit Trail": "History",
  "Security Center": "Safety",
  Operations: "System",
};

const SIMPLE_NAVIGATION = {
  "Manual Actions": "Manual",
  Plans: "Saved work",
  "Audit Trail": "History",
  Activity: "History",
  Security: "Safety",
  Operations: "System",
};

const PRODUCT_NAMES = {
  mcpmaster: "MCPMaster",
  Battle: "Battle",
  battle: "Battle",
  realmatch: "RealMatch",
  Memory: "Memory",
  memory: "Memory",
  "callgate-platform": "CallGate",
};

let updateQueued = false;
let updating = false;

function setText(element, value) {
  if (element && element.textContent !== value) element.textContent = value;
}

function productName(value) {
  const raw = String(value || "").trim();
  const repository = raw.includes("/") ? raw.split("/").pop() : raw;
  return PRODUCT_NAMES[repository] || repository || "the project";
}

function simplePhase(value) {
  const raw = String(value || "").trim();
  const phaseName = raw.includes(" · ") ? raw.split(" · ").slice(1).join(" · ") : raw;
  return SIMPLE_PHASES[phaseName] || phaseName;
}

function simpleTask(value) {
  const raw = String(value || "").trim();
  const id = raw.match(/PO-\d+/)?.[0];
  if (id && SIMPLE_TASKS[id]) return SIMPLE_TASKS[id];
  return raw.replace(/^PO-\d+\s*·\s*/, "") || "Pandora will choose the next ready step";
}

function simpleStatus(value) {
  const status = String(value || "").trim().toUpperCase();
  if (status === "LIVE") return "Live";
  if (["COMPLETE", "COMPLETED"].includes(status)) return "Ready";
  if (["ACTIVE", "IN-PROGRESS", "IN PROGRESS", "WORKING", "QUEUED-QUALIFICATION", "NOW"].includes(status)) return "Working";
  if (status === "READY" || status === "DONE") return "Ready";
  if (["NEEDS YOU", "NEEDS_YOU", "APPROVAL"].includes(status)) return "Needs You";
  if (["PARTIAL", "BLOCKED", "UNAVAILABLE", "FAILED", "ERROR", "PROBLEM"].includes(status)) return "Problem";
  if (["PLANNED", "NOT-STARTED", "NOT STARTED", "LATER"].includes(status)) return "Working";
  return status;
}

function makeDetails(label, className = "owner-inline-details") {
  const details = document.createElement("details");
  details.className = className;
  const summary = document.createElement("summary");
  summary.textContent = label;
  details.append(summary);
  return details;
}

function rewriteNavigation(root) {
  for (const button of root.querySelectorAll(".nav-button, .bottom-button")) {
    const label = button.querySelector("span:last-child");
    const simplified = SIMPLE_NAVIGATION[label?.textContent?.trim()];
    if (simplified) setText(label, simplified);
  }

  for (const button of root.querySelectorAll('[data-route="builder"]')) {
    if (button.textContent.trim() === "Manual override") setText(button, "Manual action");
  }
}

function rewriteTopLevelCopy(root) {
  const titleElement = root.querySelector(".page-title");
  const title = titleElement?.textContent?.trim();
  if (title && ROUTE_SUBTITLES[title]) {
    setText(root.querySelector(".page-subtitle"), ROUTE_SUBTITLES[title]);
  }
  if (title && SIMPLE_PAGE_TITLES[title]) setText(titleElement, SIMPLE_PAGE_TITLES[title]);
  rewriteNavigation(root);

  const connecting = root.querySelector(".demo-banner");
  if (connecting) {
    setText(connecting.querySelector("strong"), "Checking Pandora");
    setText(connecting.querySelector("p"), "Pandora is confirming that everything is ready. Manual actions stay locked until the safety checks pass.");
  }

  const error = root.querySelector(".system-banner");
  if (error) setText(error.querySelector("strong"), "Pandora needs attention");
}

function rewriteGate(gate, label, detail, healthyText = "OK", warningText = "CHECK") {
  if (!gate) return;
  const strong = gate.querySelector("strong");
  const spans = Array.from(gate.children).filter((child) => child.tagName === "SPAN");
  const badge = gate.querySelector(".badge");
  const healthy = gate.querySelector(".status-dot")?.classList.contains("healthy");
  setText(strong, label);
  if (spans[0]) setText(spans[0], detail);
  setText(badge, healthy ? healthyText : warningText);
}

function rewriteNextCard(card) {
  if (!card) return;
  setText(card.querySelector(".card-title"), "What happens next");
  setText(card.querySelector(".card-subtitle"), "Pandora chose the next ready step");
  const badge = card.querySelector(".badge");
  if (badge) setText(badge, simpleStatus(badge.textContent));

  const rows = Array.from(card.querySelectorAll(":scope > .list > .list-row"));
  const technicalRows = [];
  for (const row of rows) {
    const label = row.querySelector(".list-detail");
    const value = row.querySelector(".list-meta");
    const originalLabel = label?.textContent?.trim();
    const fullValue = value?.getAttribute("title") || value?.textContent || "";
    if (originalLabel === "Task") {
      setText(label, "Step");
      const simplified = simpleTask(fullValue);
      setText(value, simplified);
      value?.setAttribute("title", simplified);
    } else if (originalLabel === "Repository") {
      setText(label, "Project");
      const simplified = productName(fullValue);
      setText(value, simplified);
      value?.setAttribute("title", simplified);
    } else {
      technicalRows.push(row);
    }
  }

  if (technicalRows.length) {
    const details = makeDetails("See technical details");
    const body = document.createElement("div");
    body.className = "owner-details-list";
    technicalRows.forEach((row) => body.append(row));
    details.append(body);
    card.querySelector(":scope > .list")?.append(details);
  }
}

function rewritePhaseCard(card) {
  if (!card) return;
  setText(card.querySelector(".card-title"), "Work stages");
  setText(card.querySelector(".card-subtitle"), "Completed in the right order");
  for (const row of card.querySelectorAll(".list-row")) {
    const title = row.querySelector(".list-title");
    const detail = row.querySelector(".list-detail");
    const badge = row.querySelector(".badge");
    const rawTitle = title?.textContent || "";
    const phaseId = rawTitle.match(/phase-\d+/)?.[0];
    const name = simplePhase(rawTitle);
    setText(title, phaseId ? `${phaseId.replace("phase-", "Stage ")} · ${name}` : name);
    const progress = detail?.textContent?.match(/(\d+)\/(\d+)/);
    if (progress) setText(detail, `${progress[1]} of ${progress[2]} required steps done`);
    if (badge) setText(badge, simpleStatus(badge.textContent));
  }
}

function rewriteSafetyCard(card) {
  if (!card) return;
  const eyebrow = card.querySelector(".eyebrow");
  const heading = card.querySelector("h2");
  const paragraph = card.querySelector("p");
  const button = card.querySelector("button");
  setText(eyebrow, "SYSTEM SAFETY");
  setText(heading, heading?.textContent?.trim() === "Operational" ? "Ready" : "Needs attention");
  setText(paragraph, "Pandora keeps approvals, activity history, limits, and recovery protection ready in the background.");
  setText(button, "Open full system details");

  const grid = card.querySelector(":scope > .gate-grid");
  if (grid) {
    const details = makeDetails("See safety details");
    details.append(grid);
    card.append(details);
  }
}

function transformProjectOS(section) {
  if (!section || section.dataset.simpleOwnerView === "true") return;
  section.dataset.simpleOwnerView = "true";
  const children = Array.from(section.children);
  const hero = children[0];
  const metrics = children[1];
  const mainGrid = children[2];
  const safety = children[3];
  const systemGrid = children[4];
  const activity = children[5];

  const heroHeading = hero?.querySelector("h2");
  const heroText = heroHeading?.textContent || "";
  if (hero) {
    setText(hero.querySelector(".eyebrow"), "PROJECTOS STATUS");
    if (heroText.startsWith("Continuing ")) {
      setText(heroHeading, `Working on ${productName(heroText.replace("Continuing ", ""))}`);
    } else if (heroText === "Roadmap complete") {
      setText(heroHeading, "All planned work is complete");
    } else {
      setText(heroHeading, "Checking the next step");
    }
    setText(hero.querySelector("p"), "Pandora checks the real status, chooses the next ready step, and continues the work for you.");
    setText(hero.querySelector("button"), "Check again");

    const gates = hero.querySelectorAll(".gate");
    const progressText = gates[0]?.querySelector(":scope > span:not(.badge)")?.textContent || "";
    const progress = progressText.match(/(\d+)\/(\d+)/);
    rewriteGate(gates[0], "Saved proof", progress ? `${progress[1]} of ${progress[2]} steps confirmed` : "Checking saved proof");
    rewriteGate(gates[1], "Current stage", simplePhase(gates[1]?.querySelector(":scope > span:not(.badge)")?.textContent || "Checking"));
    rewriteGate(gates[2], "Next step", gates[2]?.querySelector(".status-dot")?.classList.contains("healthy") ? "Ready to continue" : "No step ready");
    const blockerText = gates[3]?.querySelector(":scope > span:not(.badge)")?.textContent || "None";
    const blockerCount = blockerText.match(/^(\d+)/)?.[1];
    const simpleBlocker = blockerText === "None"
      ? "Nothing important"
      : blockerCount
        ? `${blockerCount} things need outside access or proof`
        : "Something needs attention";
    rewriteGate(gates[3], "What is blocked", simpleBlocker, "CLEAR", "Problem");
  }

  const metricCards = metrics ? Array.from(metrics.querySelectorAll(":scope > .metric")) : [];
  const nextCard = mainGrid?.children?.[0];
  const phaseCard = mainGrid?.children?.[1];
  const nextTaskText = nextCard?.querySelector(".list-row .list-meta")?.getAttribute("title") || "";
  const metricCopy = [
    ["Overall progress", "Confirmed completed work"],
    ["Current stage", simplePhase(metricCards[1]?.querySelector(".metric-detail")?.textContent || "Checking")],
    ["Next", simpleTask(nextTaskText)],
    ["Other ready work", "Work that can safely happen at the same time"],
  ];
  metricCards.forEach((card, index) => {
    setText(card.querySelector(".metric-label"), metricCopy[index]?.[0] || card.querySelector(".metric-label")?.textContent);
    setText(card.querySelector(".metric-detail"), metricCopy[index]?.[1] || card.querySelector(".metric-detail")?.textContent);
    if (index === 2) setText(card.querySelector(".metric-value"), nextTaskText ? "Ready" : "Waiting");
  });

  rewriteNextCard(nextCard);
  rewritePhaseCard(phaseCard);
  rewriteSafetyCard(safety);

  const connectionCard = systemGrid?.children?.[0];
  const approvalsCard = systemGrid?.children?.[1];
  if (approvalsCard) {
    setText(approvalsCard.querySelector(".card-title"), "Needs your approval");
    setText(approvalsCard.querySelector(".card-subtitle"), "Only important actions that require your decision");
    systemGrid.classList.add("owner-single");
  }

  if (connectionCard || activity) {
    const completeDetails = makeDetails("See complete details", "owner-complete-details card");
    const body = document.createElement("div");
    body.className = "owner-complete-details-body";
    if (connectionCard) body.append(connectionCard);
    if (activity) body.append(activity);
    completeDetails.append(body);
    section.append(completeDetails);
  }
}

function applySimpleLanguage() {
  if (updating) return;
  updating = true;
  try {
    const root = document.querySelector("#app");
    if (!root) return;
    rewriteTopLevelCopy(root);
    transformProjectOS(root.querySelector('section[data-screen="projectos"]'));
  } finally {
    updating = false;
  }
}

function queueUpdate() {
  if (updateQueued) return;
  updateQueued = true;
  queueMicrotask(() => {
    updateQueued = false;
    applySimpleLanguage();
  });
}

const app = document.querySelector("#app");
if (app) {
  new MutationObserver(queueUpdate).observe(app, { childList: true, subtree: true });
}
queueUpdate();

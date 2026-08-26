const {
  BRAND_MARK, USER_AVATAR, icons, state, app, esc, normalizeStatus, isComplete, isActive, isBlocked, cleanName, projectName, projectInitials, formatPhase, timeAgo, formatExpiry, formatTool, projectForPlan, projectForEvent, eventMessage, eventKind, deriveProjects
} = window.PandorasOwnerData;
const { button, badge, statusSummary, pendingPlans, attentionCount } = window.PandorasOwnerRuntime;

function sectionHeader(title, actionLabel, actionKey) {
  return `<div class="owner-section-heading">
    <h2>${esc(title)}</h2>
    ${actionLabel ? `<button type="button" class="owner-section-link" ${actionKey ? `data-action="${esc(actionKey)}"` : 'data-route="projects"'}>${esc(actionLabel)}</button>` : ''}
  </div>`;
}

// STEP 0: Dashboard Home Screen (Matching Image 1)
function renderDashboardHome() {
  const wizard = state.wizardData;
  return `<div class="owner-screen owner-dashboard-screen">
    
    <!-- AI Command Box Card -->
    <section class="owner-card owner-command-card">
      <div class="owner-command-header">
        <span class="owner-spark-icon">${icons.sparkles}</span>
        <div class="owner-command-input-wrap">
          <input type="text" class="owner-command-input" id="pandora-intent-input" placeholder="What do you want Pandora to do?" value="${esc(wizard.prompt)}" data-action="update-prompt" />
          <div class="owner-command-tools">
            <button type="button" class="owner-tool-icon-btn" data-action="voice-input" title="Voice Input">${icons.mic}</button>
            <button type="button" class="owner-tool-icon-btn" data-action="attach-file" title="Attach File">${icons.paperclip}</button>
            <button type="button" class="owner-command-submit-btn" data-action="submit-intent" aria-label="Send Intent">${icons.arrow}</button>
          </div>
        </div>
      </div>
      <div class="owner-quick-chips">
        <button type="button" class="owner-quick-chip" data-action="quick-prompt" data-prompt="Build an online booking system">
          <span>📅</span><span>Build an online booking system</span>
        </button>
        <button type="button" class="owner-quick-chip" data-action="quick-prompt" data-prompt="Automate customer follow-ups">
          <span>👤</span><span>Automate customer follow-ups</span>
        </button>
        <button type="button" class="owner-quick-chip" data-action="quick-prompt" data-prompt="Improve my website">
          <span>📈</span><span>Improve my website</span>
        </button>
      </div>
    </section>

    <!-- Needs You (2) -->
    <section class="owner-section">
      ${sectionHeader('Needs You (2)', 'View all', 'open-needs-you')}
      <div class="owner-needs-grid">
        <div class="owner-card owner-needs-card">
          <div class="owner-needs-top">
            <div class="owner-needs-icon pink">🛍️</div>
            <div class="owner-needs-copy">
              <strong>New booking system ready for review</strong>
              <p>Pandora finished building and checking it.</p>
            </div>
          </div>
          <button type="button" class="owner-text-link-btn" data-action="start-review">Review →</button>
        </div>

        <div class="owner-card owner-needs-card">
          <div class="owner-needs-top">
            <div class="owner-needs-icon blue">${icons.facebook}</div>
            <div class="owner-needs-copy">
              <strong>Connect Facebook</strong>
              <p>Needed before Pandora can automate customer inquiries.</p>
            </div>
          </div>
          <button type="button" class="owner-text-link-btn" data-action="open-connection" data-key="facebook:fb1">Connect →</button>
        </div>
      </div>
    </section>

    <!-- Pandora is working • Live -->
    <section class="owner-section">
      <div class="owner-section-heading">
        <h2>Pandora is working <span class="owner-live-dot">• Live</span></h2>
        <button type="button" class="owner-section-link" data-route="activity">View all</button>
      </div>
      <div class="owner-card owner-working-card">
        <div class="owner-working-row">
          <div class="owner-working-icon amber">${icons.code}</div>
          <div class="owner-working-copy">
            <strong>Building employee portal</strong>
            <small>Designing ✓ Building ✓ Testing...</small>
          </div>
          <span class="owner-pill amber">In progress</span>
        </div>
        <div class="owner-working-row">
          <div class="owner-working-icon green">${icons.users}</div>
          <div class="owner-working-copy">
            <strong>Preparing today's customer follow-ups</strong>
            <small>42 customers analyzed</small>
          </div>
          <span class="owner-pill green">Analyzing</span>
        </div>
        <div class="owner-working-row">
          <div class="owner-working-icon purple">${icons.shield}</div>
          <div class="owner-working-copy">
            <strong>Monitoring booking system</strong>
            <small>Operating normally</small>
          </div>
          <span class="owner-pill green-check">Healthy</span>
        </div>
      </div>
    </section>

    <!-- Business Pulse -->
    <section class="owner-section">
      ${sectionHeader('Business Pulse', 'View dashboard', 'open-pulse')}
      <div class="owner-pulse-grid">
        <div class="owner-card owner-pulse-card">
          <span class="owner-pulse-icon">${icons.user}</span>
          <div class="owner-pulse-copy">
            <small>Customers</small>
            <strong>34 inquiries</strong>
            <span class="owner-pulse-sub green">↑ 12% this week</span>
          </div>
        </div>

        <div class="owner-card owner-pulse-card">
          <span class="owner-pulse-icon">${icons.calendar}</span>
          <div class="owner-pulse-copy">
            <small>Bookings</small>
            <strong>18 completed</strong>
            <span class="owner-pulse-sub amber">2 need attention</span>
          </div>
        </div>

        <div class="owner-card owner-pulse-card">
          <span class="owner-pulse-icon">💲</span>
          <div class="owner-pulse-copy">
            <small>Revenue</small>
            <strong>₱84,250</strong>
            <span class="owner-pulse-sub green">Verified ✓</span>
          </div>
        </div>

        <div class="owner-card owner-pulse-card">
          <span class="owner-pulse-icon">⚙️</span>
          <div class="owner-pulse-copy">
            <small>Operations</small>
            <strong>96% normal</strong>
            <span class="owner-pulse-sub amber">1 issue</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Pandora Recommends -->
    <section class="owner-card owner-recommends-card">
      <div class="owner-recommends-top">
        <div class="owner-spark-icon-lg">${icons.sparkles}</div>
        <div class="owner-recommends-copy">
          <span class="owner-kicker-sm">PANDORA RECOMMENDS</span>
          <p><strong>7 inquiries went unanswered after 6 PM this week.</strong> Pandora can create an automatic after-hours response and booking flow.</p>
        </div>
      </div>
      <div class="owner-recommends-actions">
        <button type="button" class="owner-button primary-red" data-action="quick-prompt" data-prompt="Create an automatic after-hours response and booking flow">Automate this</button>
        <button type="button" class="owner-text-link-sm" data-action="open-recommend-why">Why?</button>
      </div>
    </section>

    <!-- My Systems -->
    <section class="owner-section">
      ${sectionHeader('My Systems', 'See all systems →', 'open-systems')}
      <div class="owner-systems-row">
        <div class="owner-card owner-system-chip">
          <span class="owner-sys-icon">📅</span>
          <div>
            <strong>Booking</strong>
            <small class="green">• Live • Healthy</small>
          </div>
        </div>
        <div class="owner-card owner-system-chip">
          <span class="owner-sys-icon">🌐</span>
          <div>
            <strong>Website</strong>
            <small class="green">• Live • Healthy</small>
          </div>
        </div>
        <div class="owner-card owner-system-chip">
          <span class="owner-sys-icon">💬</span>
          <div>
            <strong>Follow-ups</strong>
            <small class="blue">• Running</small>
          </div>
        </div>
        <div class="owner-card owner-system-chip">
          <span class="owner-sys-icon">👥</span>
          <div>
            <strong>Employee Portal</strong>
            <small class="amber">• Building</small>
          </div>
        </div>
      </div>
    </section>

    <!-- Recent activity -->
    <section class="owner-section">
      ${sectionHeader('Recent activity', 'View all', 'activity')}
      <div class="owner-card owner-activity-timeline-card">
        <div class="owner-timeline-item">
          <span class="owner-timeline-dot green">${icons.check}</span>
          <div class="owner-timeline-content">
            <strong>Pandora confirmed 3 new bookings.</strong>
            <time>9:42 AM</time>
          </div>
        </div>
        <div class="owner-timeline-item">
          <span class="owner-timeline-dot blue">${icons.check}</span>
          <div class="owner-timeline-content">
            <strong>Your customer reminder automation completed.</strong>
            <time>9:11 AM</time>
          </div>
        </div>
        <div class="owner-timeline-item">
          <span class="owner-timeline-dot amber">${icons.alert}</span>
          <div class="owner-timeline-content">
            <strong>Pandora found an issue with Facebook connection.</strong>
            <time>8:46 AM</time>
          </div>
        </div>
        <div class="owner-timeline-item">
          <span class="owner-timeline-dot purple">🚀</span>
          <div class="owner-timeline-content">
            <strong>Your website update went live.</strong>
            <time>Yesterday</time>
          </div>
        </div>
      </div>
    </section>
  </div>`;
}

// STEP 2: Understand View (Matching Image 3)
function renderUnderstandStep() {
  const wizard = state.wizardData;
  return `<div class="owner-screen owner-wizard-screen">
    <div class="owner-wizard-intro">
      <h1>Here's what I understand <span class="owner-spark-inline">${icons.sparkles}</span></h1>
      <p>Tell me if I got this right or if you'd like to change anything.</p>
    </div>

    <!-- Goal Pink Box -->
    <div class="owner-card owner-goal-card">
      <span class="owner-kicker-red">YOUR GOAL</span>
      <h2>${esc(wizard.goal)}</h2>
    </div>

    <!-- This will include 6-item grid -->
    <section class="owner-section">
      <h3 class="owner-group-title">This will include</h3>
      <div class="owner-include-grid">
        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">📅</span>
          <div>
            <strong>Customer booking page</strong>
            <p>Customers can choose service, date and time</p>
          </div>
        </div>

        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">👤</span>
          <div>
            <strong>Technician schedule</strong>
            <p>Your staff can manage their appointments</p>
          </div>
        </div>

        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">🔔</span>
          <div>
            <strong>Automatic confirmations</strong>
            <p>Customers get booking confirmation instantly</p>
          </div>
        </div>

        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">💬</span>
          <div>
            <strong>Reminders</strong>
            <p>Automatic reminders before the appointment</p>
          </div>
        </div>

        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">📊</span>
          <div>
            <strong>Owner dashboard</strong>
            <p>See bookings, jobs and business overview</p>
          </div>
        </div>

        <div class="owner-card owner-include-item">
          <span class="owner-inc-icon">📱</span>
          <div>
            <strong>Mobile friendly</strong>
            <p>Looks great on phones, tablets and desktop</p>
          </div>
        </div>
      </div>
    </section>

    <!-- A few things I'll need from you (Yellow card) -->
    <div class="owner-card owner-need-card">
      <div class="owner-need-header">
        <span class="owner-need-icon">💡</span>
        <strong>A few things I'll need from you</strong>
      </div>
      <ul class="owner-need-list">
        <li><span class="check-mark">✓</span> Your business logo (optional)</li>
        <li><span class="check-mark">✓</span> Your working hours</li>
        <li><span class="check-mark">✓</span> Service types and pricing</li>
        <li><span class="check-mark">✓</span> Payment and messaging setup (we'll connect this later)</li>
      </ul>
    </div>

    <!-- Before we start (Blue card) -->
    <div class="owner-card owner-safety-card">
      <div class="owner-safety-header">
        <span class="owner-safety-icon">🛡️</span>
        <strong>Before we start</strong>
      </div>
      <div class="owner-safety-grid">
        <div>
          <strong>🔒 Safe & reversible</strong>
          <p>You can review everything before anything goes live</p>
        </div>
        <div>
          <strong>⏱️ You're in control</strong>
          <p>I'll ask for approval for important actions</p>
        </div>
      </div>
    </div>

    <!-- Bottom Step Actions -->
    <div class="owner-wizard-actions">
      <button type="button" class="owner-button secondary-outline" data-action="edit-goal">Change something</button>
      <button type="button" class="owner-button primary-red" data-action="proceed-to-build">Looks good, continue →</button>
    </div>
  </div>`;
}

// STEP 3: Build View (Matching Image 4)
function renderBuildStep() {
  const wizard = state.wizardData;
  const items = [
    { title: "Understanding your business", desc: "Got it!", done: true },
    { title: "Designing the experience", desc: "Creating layouts and flows", done: true },
    { title: "Building the system", desc: "Writing code and connecting things", active: true },
    { title: "Connecting your tools", desc: "Integrations and setup", pending: true },
    { title: "Testing everything", desc: "Making sure it works perfectly", pending: true },
    { title: "Verifying & preparing for you", desc: "Final checks and review", pending: true },
  ];

  return `<div class="owner-screen owner-wizard-screen">
    <div class="owner-wizard-intro text-center">
      <h1>Pandora is working on it <span class="owner-spark-inline">${icons.sparkles}</span></h1>
      <p>This usually takes a few minutes. You can close the app and we'll continue in the background.</p>
    </div>

    <!-- Hero 3D Red Apple Visual -->
    <div class="owner-build-hero">
      <div class="owner-glowing-apple-wrap">
        <img src="${BRAND_MARK}" alt="Building System" class="owner-glowing-apple-img" />
        <div class="owner-pulse-ring"></div>
      </div>
    </div>

    <!-- Progress Checklist Card -->
    <div class="owner-card owner-build-progress-card">
      <div class="owner-build-progress-header">
        <strong>Building your booking system</strong>
        <span class="owner-pill amber-live">In progress</span>
      </div>
      <div class="owner-build-checklist">
        ${items.map((it) => `
          <div class="owner-build-item ${it.done ? 'done' : it.active ? 'active' : 'pending'}">
            <span class="owner-build-icon">
              ${it.done ? icons.check : it.active ? `<span class="owner-spinner"></span>` : '—'}
            </span>
            <div class="owner-build-copy">
              <strong>${esc(it.title)}</strong>
              <small>${esc(it.desc)}</small>
            </div>
          </div>
        `).join('')}
      </div>
    </div>

    <!-- Live Preview Card snippet -->
    <div class="owner-card owner-preview-snippet-card">
      <div class="owner-preview-snippet-top">
        <div>
          <strong>Here's a preview while we build</strong>
          <p>Interactive preview ready for testing.</p>
        </div>
        <button type="button" class="owner-button primary-red-sm" data-action="open-full-preview">Open full preview ↗</button>
      </div>
    </div>

    <!-- Notification Safety Notice -->
    <div class="owner-card owner-notice-card">
      <span class="notice-icon">🔒</span>
      <div class="notice-copy">
        <strong>We'll notify you when it's ready</strong>
        <p>You'll get a notification and see it in Needs You.</p>
      </div>
    </div>
  </div>`;
}

// STEP 4 & 5: Preview & Try It Out View (Matching Images 2 & 5)
function renderPreviewStep() {
  const wizard = state.wizardData;
  const mode = wizard.previewMode || 'mobile';
  const tab = wizard.previewTab || 'home';

  return `<div class="owner-screen owner-preview-screen">
    <div class="owner-preview-header-bar">
      <div>
        <h1>Try it out! <span class="owner-spark-inline">${icons.sparkles}</span></h1>
        <p>This is an interactive preview of your booking system. Explore it like your customers will.</p>
      </div>
      <!-- Mode Switcher -->
      <div class="owner-mode-switcher">
        <button type="button" class="owner-mode-btn ${mode === 'mobile' ? 'active' : ''}" data-action="set-preview-mode" data-mode="mobile">
          ${icons.phone} <span>Mobile</span>
        </button>
        <button type="button" class="owner-mode-btn ${mode === 'tablet' ? 'active' : ''}" data-action="set-preview-mode" data-mode="tablet">
          ${icons.tablet} <span>Tablet</span>
        </button>
        <button type="button" class="owner-mode-btn ${mode === 'desktop' ? 'active' : ''}" data-action="set-preview-mode" data-mode="desktop">
          ${icons.desktop} <span>Desktop</span>
        </button>
      </div>
    </div>

    <div class="owner-preview-body-grid">
      <!-- Device Frame -->
      <div class="owner-device-frame-wrap ${mode}">
        <div class="owner-device-phone">
          <div class="owner-phone-speaker"></div>
          
          <!-- Embedded Booking System App -->
          <div class="owner-phone-screen-content">
            <!-- App Header -->
            <header class="aircon-app-header">
              <div class="aircon-brand">
                <span class="aircon-logo">❄️</span>
                <div>
                  <strong>Aircon Care PH</strong>
                  <small>Fast. Reliable. Professional.</small>
                </div>
              </div>
              <span class="aircon-status-badge">Available Now</span>
            </header>

            <!-- Active Tab Content -->
            <div class="aircon-app-body">
              ${tab === 'home' ? `
                <div class="aircon-hero-banner">
                  <h2>Book your aircon service</h2>
                  <p>Professional technicians at your service.</p>
                </div>

                <div class="aircon-form-card">
                  <div class="aircon-field">
                    <label>1 Select Service</label>
                    <select class="aircon-select" data-action="select-preview-service">
                      <option ${wizard.selectedService === 'Cleaning Service' ? 'selected' : ''}>Cleaning Service (₱999)</option>
                      <option ${wizard.selectedService === 'Repair & Diagnostics' ? 'selected' : ''}>Repair & Diagnostics (₱1,200)</option>
                      <option ${wizard.selectedService === 'Installation' ? 'selected' : ''}>New Installation (₱3,500)</option>
                    </select>
                  </div>

                  <div class="aircon-field">
                    <label>2 Select Date</label>
                    <input type="text" class="aircon-input" value="${esc(wizard.selectedDate)}" data-action="update-preview-date" />
                  </div>

                  <div class="aircon-field">
                    <label>3 Select Time</label>
                    <select class="aircon-select" data-action="select-preview-time">
                      <option>09:00 AM – 11:00 AM</option>
                      <option>01:00 PM – 03:00 PM</option>
                      <option>04:00 PM – 06:00 PM</option>
                    </select>
                  </div>

                  <div class="aircon-field">
                    <label>4 Your Location</label>
                    <input type="text" class="aircon-input" value="${esc(wizard.location)}" data-action="update-preview-location" />
                  </div>

                  <button type="button" class="aircon-submit-btn" data-action="submit-preview-booking">
                    Continue to details →
                  </button>
                </div>
              ` : tab === 'bookings' ? `
                <div class="aircon-tab-page">
                  <h3>My Bookings</h3>
                  <div class="aircon-booking-item">
                    <div class="top">
                      <strong>Aircon Cleaning Service</strong>
                      <span class="tag green">Confirmed</span>
                    </div>
                    <small>May 20, 2025 • 09:00 AM</small>
                    <p>123 Rizal St., Makati City</p>
                  </div>
                </div>
              ` : tab === 'services' ? `
                <div class="aircon-tab-page">
                  <h3>Our Services</h3>
                  <div class="aircon-service-list">
                    <div class="service"><strong>Split-Type Deep Cleaning</strong><span>₱1,200</span></div>
                    <div class="service"><strong>Window-Type Cleaning</strong><span>₱800</span></div>
                    <div class="service"><strong>Freon Charging</strong><span>₱1,500</span></div>
                  </div>
                </div>
              ` : `
                <div class="aircon-tab-page">
                  <h3>Help & Support</h3>
                  <p>Need assistance with your aircon appointment? Contact technician hotlines 24/7.</p>
                </div>
              `}
            </div>

            <!-- Phone Sub-Navigation -->
            <nav class="aircon-app-nav">
              <button type="button" class="${tab === 'home' ? 'active' : ''}" data-action="set-preview-tab" data-tab="home">
                <span>🏠</span><span>Home</span>
              </button>
              <button type="button" class="${tab === 'bookings' ? 'active' : ''}" data-action="set-preview-tab" data-tab="bookings">
                <span>📅</span><span>Bookings</span>
              </button>
              <button type="button" class="${tab === 'services' ? 'active' : ''}" data-action="set-preview-tab" data-tab="services">
                <span>🛠️</span><span>Services</span>
              </button>
              <button type="button" class="${tab === 'help' ? 'active' : ''}" data-action="set-preview-tab" data-tab="help">
                <span>❓</span><span>Help</span>
              </button>
            </nav>
          </div>
        </div>
      </div>

      <!-- Right Side Panel -->
      <div class="owner-preview-side-panel">
        <!-- What you can try -->
        <div class="owner-card owner-side-card">
          <h3>What you can try</h3>
          <ul class="owner-try-list">
            <li>Book a service</li>
            <li>Pick different dates</li>
            <li>View confirmations</li>
            <li>Check your dashboard</li>
          </ul>
        </div>

        <!-- Give Pandora feedback -->
        <div class="owner-card owner-side-card">
          <h3>Give Pandora feedback</h3>
          <textarea class="owner-feedback-textarea" placeholder="Type feedback or changes you'd like..." data-action="update-feedback">${esc(wizard.feedbackText)}</textarea>
          <button type="button" class="owner-button voice-feedback-btn" data-action="voice-feedback">
            ${icons.mic} <span>Record voice feedback</span>
          </button>
        </div>

        <!-- Key features in this preview -->
        <div class="owner-card owner-side-card">
          <h3>Key features in this preview</h3>
          <ul class="owner-features-check-list">
            <li><span class="green-check">✓</span> Real booking flow</li>
            <li><span class="green-check">✓</span> Automatic confirmations</li>
            <li><span class="green-check">✓</span> Technician management</li>
            <li><span class="green-check">✓</span> Dashboard overview</li>
          </ul>
        </div>
      </div>
    </div>

    <!-- Sticky Bottom Bar -->
    <div class="owner-preview-bottom-bar">
      <div>
        <strong>Looks good so far!</strong>
        <p>When you're happy, we'll prepare everything to go live.</p>
      </div>
      <button type="button" class="owner-button primary-red" data-action="approve-and-publish">Looks good, continue →</button>
    </div>
  </div>`;
}

function renderHome() {
  const step = state.wizardStep || 0;
  if (step === 2) return renderUnderstandStep();
  if (step === 3) return renderBuildStep();
  if (step === 4 || step === 5) return renderPreviewStep();
  return renderDashboardHome();
}

function renderProjects() {
  const projects = deriveProjects();
  return `<div class="owner-screen">
    <div class="owner-page-intro"><span class="owner-kicker">Your portfolio</span><h1>Systems & Projects</h1><p>Progress is calculated only from tasks recorded in the current ProjectOS status.</p></div>
    <div class="owner-project-grid">${projects.length ? projects.map((project) => `<article class="owner-card owner-project-card">
      <button type="button" class="owner-project-open" data-action="open-project" data-id="${esc(project.id)}">
        <span class="owner-project-card-top"><span class="owner-project-mark large">${esc(project.initials)}</span><span class="owner-project-card-title"><strong>${esc(project.name)}</strong><span>${esc(project.repository)}</span></span><b>${project.progress === null ? '—' : `${project.progress}%`}</b></span>
        ${progressMarkup(project)}
        <span class="owner-progress-label">Evidence-based progress · ${project.completed} of ${project.total} recorded tasks complete</span>
        <span class="owner-project-details"><span><small>Current phase</small><strong>${esc(project.phase)}</strong></span><span><small>Next milestone</small><strong>${esc(project.nextMilestone)}</strong></span></span>
        <span class="owner-project-card-footer"><span>${project.lastUpdated ? `Updated ${timeAgo(project.lastUpdated)}` : 'Update time unavailable'}</span><span>Open project ${icons.arrow}</span></span>
      </button>
    </article>`).join('') : `<div class="owner-card owner-empty"><span>${icons.projects}</span><h2>No projects found</h2><p>The canonical status does not currently contain project tasks.</p></div>`}</div>
  </div>`;
}

function progressMarkup(project) {
  if (project.progress === null) return `<span class="owner-progress-unavailable">Progress unavailable</span>`;
  return `<div class="owner-progress" aria-label="${project.progress}% evidence-based progress"><span style="width:${Math.max(0, Math.min(100, project.progress))}%"></span></div>`;
}

window.PandorasOwnerScreenCore = Object.freeze({
  sectionHeader, renderDashboardHome, renderUnderstandStep, renderBuildStep, renderPreviewStep, renderHome, renderProjects, progressMarkup
});

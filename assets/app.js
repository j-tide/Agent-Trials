const DATA_ROOT = new URL("../data/", import.meta.url);
const STORAGE_KEY = "agent-trials.progress.v2";
const LEGACY_STORAGE_KEY = "agent-trials.progress.v1";
const DAILY_GOAL = 10;
const PAGE_SIZE = 25;

const VIEW_LABELS = {
  dashboard: "今日训练",
  practice: "开始刷题",
  library: "题库浏览",
  report: "学习报告"
};

const appView = document.getElementById("appView");
const appShell = document.getElementById("appShell");
const toastElement = document.getElementById("toast");

const state = {
  catalog: null,
  catalogMap: new Map(),
  moduleMap: new Map(),
  packPromises: new Map(),
  view: window.location.hash.slice(1) in VIEW_LABELS ? window.location.hash.slice(1) : "dashboard",
  dashboardTab: "today",
  library: { query: "", category: "all", source: "all", filter: "all", page: 1 },
  practice: null,
  progress: loadProgress(),
  toastTimer: null
};

function icon(name) {
  const paths = {
    arrowRight: '<path d="M4 12h15M13 6l6 6-6 6"/>',
    arrowLeft: '<path d="M20 12H5M11 6l-6 6 6 6"/>',
    arrowUpRight: '<path d="M5 19 19 5M9 5h10v10"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    clock: '<circle cx="12" cy="12" r="8"/><path d="M12 7v5l3 2"/>',
    flame: '<path d="M12 21c4 0 7-2.6 7-6.3 0-2.8-1.6-5.2-4.7-8.2.2 2.2-.9 3.4-2.1 4.2.2-3.5-1.4-6.1-4.7-8.7.3 3.7-3.5 5.8-3.5 9.6C4 17.9 7.2 21 12 21Z"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
    spark: '<path d="m12 2 1.4 6.6L20 10l-6.6 1.4L12 18l-1.4-6.6L4 10l6.6-1.4L12 2Z"/><path d="m19 16 .6 2.4L22 19l-2.4.6L19 22l-.6-2.4L16 19l2.4-.6L19 16Z"/>',
    shuffle: '<path d="M3 7h3c4 0 5 10 9 10h6M17 5l4 2-4 2M17 15l4 2-4 2M3 17h3c1.5 0 2.5-1.3 3.3-2.7"/>',
    book: '<path d="M5 5.5A2.5 2.5 0 0 1 7.5 3H20v15H7.5A2.5 2.5 0 0 0 5 20.5z"/><path d="M5 5.5v15M8 7h8M8 11h8"/>',
    filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
    trend: '<path d="m4 16 5-5 4 3 7-8"/><path d="M15 6h5v5"/>',
    external: '<path d="M14 5h5v5M19 5l-8 8"/><path d="M18 13v5H5V5h5"/>',
    reset: '<path d="M4 7v5h5"/><path d="M5 12a7 7 0 1 0 2-5"/>',
    info: '<circle cx="12" cy="12" r="8"/><path d="M12 11v5M12 8h.01"/>'
  };
  return `<svg class="svg-icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.info}</svg>`;
}

function todayKey(date = new Date()) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
}

function formatDate(date = new Date(), options = {}) {
  return new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "long", day: "numeric", ...options }).format(date);
}

function formatNumber(value) {
  return new Intl.NumberFormat("zh-CN").format(Number(value) || 0);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function renderParagraphs(value) {
  const text = String(value || "").trim();
  if (!text) return "<p class=\"empty-answer\">暂时没有可展示的参考答案。</p>";
  return text
    .split(/\n{2,}/)
    .map((paragraph) => `<p>${escapeHtml(paragraph).replaceAll("\n", "<br />")}</p>`)
    .join("");
}

function safeUrl(url) {
  try {
    const parsed = new URL(url);
    return ["https:", "http:"].includes(parsed.protocol) ? parsed.href : "#";
  } catch {
    return "#";
  }
}

function emptyProgress() {
  return { version: 2, dailyGoal: DAILY_GOAL, attempts: [], schedules: {}, drafts: {} };
}

function loadProgress() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
    if (saved && saved.version === 2) {
      return {
        ...emptyProgress(),
        ...saved,
        attempts: Array.isArray(saved.attempts) ? saved.attempts : [],
        schedules: saved.schedules && typeof saved.schedules === "object" ? saved.schedules : {},
        drafts: saved.drafts && typeof saved.drafts === "object" ? saved.drafts : {}
      };
    }

    const legacy = JSON.parse(localStorage.getItem(LEGACY_STORAGE_KEY) || "null");
    if (legacy && Array.isArray(legacy.attempts)) {
      const migrated = emptyProgress();
      migrated.attempts = legacy.attempts.map((attempt) => ({
        questionId: attempt.questionId,
        day: attempt.day || todayKey(),
        reviewedAt: attempt.createdAt || new Date().toISOString(),
        rating: attempt.isCorrect ? "remember" : "unknown",
        answerLength: 0,
        legacy: true
      }));
      migrated.attempts.forEach((attempt) => updateSchedule(migrated, attempt.questionId, attempt.rating, attempt.reviewedAt));
      return migrated;
    }
  } catch (error) {
    console.warn("Unable to read saved progress", error);
  }
  return emptyProgress();
}

function saveProgress() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state.progress));
  } catch (error) {
    showToast("当前浏览器无法保存进度，请检查存储权限。", "error");
  }
}

function updateSchedule(progress, questionId, rating, reviewedAt = new Date().toISOString()) {
  const previous = progress.schedules[questionId] || { repetitions: 0, intervalDays: 0, lastRating: null };
  const intervals = {
    remember: [1, 3, 7, 14, 30, 60, 90],
    unsure: [1, 2, 4, 7, 14, 30],
    unknown: [1, 1, 1, 2, 4]
  };
  const nextRepetition = rating === "remember" ? previous.repetitions + 1 : rating === "unsure" ? Math.max(0, previous.repetitions) : 0;
  const sequence = intervals[rating] || intervals.unknown;
  const intervalDays = sequence[Math.min(nextRepetition, sequence.length - 1)];
  const nextReview = new Date(new Date(reviewedAt).getTime() + intervalDays * 86400000);
  progress.schedules[questionId] = {
    repetitions: nextRepetition,
    intervalDays,
    lastRating: rating,
    lastReviewedAt: reviewedAt,
    nextReviewAt: nextReview.toISOString()
  };
}

async function fetchJson(path) {
  const response = await fetch(new URL(path, DATA_ROOT));
  if (!response.ok) throw new Error(`Unable to load ${path}: ${response.status}`);
  return response.json();
}

async function loadPack(packId) {
  if (!state.packPromises.has(packId)) {
    const pack = state.catalog.packs.find((item) => item.id === packId);
    state.packPromises.set(packId, fetchJson(pack?.path || `packs/${packId}.json`));
  }
  return state.packPromises.get(packId);
}

async function loadQuestion(questionId) {
  const meta = state.catalogMap.get(questionId);
  if (!meta) return null;
  const pack = await loadPack(meta.packId);
  return pack.questions.find((question) => question.id === questionId) || meta;
}

function getRecord(questionId) {
  return state.progress.schedules[questionId] || null;
}

function isDue(questionId) {
  const record = getRecord(questionId);
  return Boolean(record && record.nextReviewAt && new Date(record.nextReviewAt).getTime() <= Date.now());
}

function getQuestionStatus(questionId) {
  const record = getRecord(questionId);
  if (!record) return "new";
  if (isDue(questionId)) return "due";
  if (record.lastRating === "remember" && record.repetitions >= 3) return "mastered";
  return "learning";
}

function statusLabel(status) {
  return { new: "未开始", due: "待复习", learning: "学习中", mastered: "已掌握" }[status] || "未开始";
}

function statusClass(status) {
  return status === "due" ? "due" : status === "mastered" ? "mastered" : "";
}

function getAttemptsForDay(day = todayKey()) {
  return state.progress.attempts.filter((attempt) => attempt.day === day);
}

function getTodayCount() {
  return new Set(getAttemptsForDay().map((attempt) => attempt.questionId)).size;
}

function getAccuracy(attempts = state.progress.attempts) {
  if (!attempts.length) return null;
  return Math.round((attempts.filter((attempt) => attempt.rating === "remember").length / attempts.length) * 100);
}

function getDueCount() {
  if (!state.catalog) return 0;
  return state.catalog.questions.filter((question) => isDue(question.id)).length;
}

function getStreak() {
  const activeDays = new Set(state.progress.attempts.map((attempt) => attempt.day));
  let streak = 0;
  const cursor = new Date();
  while (activeDays.has(todayKey(cursor))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

function questionMastery(questionId) {
  const record = getRecord(questionId);
  if (!record) return 0;
  const base = Math.min(72, record.repetitions * 18);
  const modifier = record.lastRating === "remember" ? 24 : record.lastRating === "unsure" ? 8 : 0;
  return Math.min(100, base + modifier);
}

function categoryMastery(categoryId) {
  const questions = state.catalog.questions.filter((question) => question.primaryModuleParentId === categoryId);
  const reviewed = questions.filter((question) => getRecord(question.id));
  if (!reviewed.length) return { value: 0, reviewed: 0, total: questions.length };
  return {
    value: Math.round(reviewed.reduce((sum, question) => sum + questionMastery(question.id), 0) / reviewed.length),
    reviewed: reviewed.length,
    total: questions.length
  };
}

function stableHash(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) hash = (hash << 5) - hash + value.charCodeAt(index) | 0;
  return Math.abs(hash);
}

function uniqueQuestions(rows) {
  const seen = new Set();
  return rows.filter((question) => {
    if (seen.has(question.id)) return false;
    seen.add(question.id);
    return true;
  });
}

function getReviewQueue(limit = DAILY_GOAL) {
  const due = state.catalog.questions
    .filter((question) => isDue(question.id))
    .sort((a, b) => new Date(getRecord(a.id).nextReviewAt) - new Date(getRecord(b.id).nextReviewAt));
  const weak = state.catalog.questions
    .filter((question) => getRecord(question.id) && !isDue(question.id))
    .sort((a, b) => questionMastery(a.id) - questionMastery(b.id));
  return uniqueQuestions([...due, ...weak]).slice(0, limit);
}

function getDailyQueue(limit = state.progress.dailyGoal || DAILY_GOAL) {
  const review = getReviewQueue(limit);
  if (review.length >= limit) return review;
  const reviewIds = new Set(review.map((question) => question.id));
  const fresh = state.catalog.questions
    .filter((question) => !reviewIds.has(question.id) && !getRecord(question.id) && question.hasReferenceAnswer)
    .sort((a, b) => stableHash(`${a.id}-${todayKey()}`) - stableHash(`${b.id}-${todayKey()}`));
  return uniqueQuestions([...review, ...fresh]).slice(0, limit);
}

function getWeakQueue(limit = DAILY_GOAL) {
  return state.catalog.questions
    .filter((question) => getRecord(question.id) && questionMastery(question.id) < 70)
    .sort((a, b) => questionMastery(a.id) - questionMastery(b.id))
    .slice(0, limit);
}

function difficultyLabel(level) {
  return { 1: "基础", 2: "基础", 3: "进阶", 4: "挑战", 5: "挑战" }[level] || "进阶";
}

function questionMeta(question) {
  return `${question.primaryModuleLabel || question.category || question.rootCategory} · ${question.estimatedMinutes || 8} 分钟`;
}

function moduleLabel(moduleId) {
  return state.moduleMap.get(moduleId)?.label || moduleId;
}

function showToast(message) {
  toastElement.textContent = message;
  toastElement.classList.add("is-visible");
  window.clearTimeout(state.toastTimer);
  state.toastTimer = window.setTimeout(() => toastElement.classList.remove("is-visible"), 2600);
}

function updateShell() {
  document.querySelectorAll("[data-view]").forEach((item) => item.classList.toggle("is-active", item.dataset.view === state.view));
  document.querySelector("[data-breadcrumb]").textContent = VIEW_LABELS[state.view] || VIEW_LABELS.dashboard;
  document.querySelector("[data-today-label]").textContent = formatDate(new Date(), { weekday: "short" });
  document.querySelector("[data-streak]").textContent = getStreak();
  document.querySelector("[data-catalog-title]").textContent = state.catalog?.source?.title || "统一题库";
  document.querySelector("[data-catalog-count]").textContent = state.catalog ? `${formatNumber(state.catalog.stats.questionCount)} 道题 · ${state.catalog.stats.categoryCount} 个知识域` : "加载中…";
  const practiceBadge = document.querySelector('[data-nav-count="practice"]');
  if (practiceBadge) practiceBadge.textContent = getDueCount() || (state.catalog ? "开始" : "—");
}

function renderMetric(markClass, label, value, hint = "", hintClass = "") {
  return `<div class="metric"><span class="metric-mark ${markClass}">${icon(markClass === "amber" ? "flame" : markClass === "blue" ? "book" : markClass === "coral" ? "clock" : "check")}</span><span><small>${label}</small><strong>${value}${hint ? `<em class="${hintClass}">${hint}</em>` : ""}</strong></span></div>`;
}

function renderQueueRows(questions, emptyText = "今天没有需要处理的题目。") {
  if (!questions.length) return `<div class="queue-empty">${emptyText}</div>`;
  return questions.map((question, index) => {
    const status = getQuestionStatus(question.id);
    return `<button class="queue-row" type="button" data-action="open-question" data-id="${escapeHtml(question.id)}">
      <span class="queue-index ${statusClass(status)} ${status === "mastered" ? "done" : ""}">${status === "mastered" ? icon("check") : String(index + 1).padStart(2, "0")}</span>
      <span><strong class="queue-row-title">${escapeHtml(question.title)}</strong><span class="queue-row-meta"><span>${escapeHtml(question.primaryModuleLabel || question.category || question.rootCategory)}</span><i></i><span>${question.estimatedMinutes || 8} min</span></span></span>
      <span class="status-tag ${statusClass(status)}">${statusLabel(status)}</span>
    </button>`;
  }).join("");
}

function renderMasteryRows() {
  const categories = [...state.catalog.categories]
    .map((category) => ({ ...category, mastery: categoryMastery(category.id) }))
    .sort((a, b) => (b.mastery.reviewed - a.mastery.reviewed) || (a.mastery.value - b.mastery.value));
  const rows = categories.slice(0, 4);
  return rows.map((category, index) => `<div class="mastery-row"><span class="mastery-label">${escapeHtml(category.label)}</span><b class="mastery-value">${category.mastery.reviewed ? `${category.mastery.value}%` : "新"}</b><div class="mastery-bar"><i class="${index === 1 ? "amber" : index === 2 ? "blue" : index === 3 ? "purple" : ""}" style="width:${category.mastery.value}%"></i></div></div>`).join("");
}

function renderDashboard() {
  const dailyQueue = getDailyQueue();
  const reviewQueue = getReviewQueue();
  const activeQueue = state.dashboardTab === "review" ? reviewQueue : dailyQueue;
  const todayCount = getTodayCount();
  const goal = state.progress.dailyGoal || DAILY_GOAL;
  const accuracy = getAccuracy(getAttemptsForDay());
  const mastered = Object.values(state.progress.schedules).filter((record) => record.repetitions >= 3 && record.lastRating === "remember").length;
  const domainCount = state.catalog.stats.domainCount || state.catalog.stats.categoryCount;
  const progressPercent = Math.min(100, Math.round((todayCount / goal) * 100));
  const focus = getWeakQueue(3).length ? getWeakQueue(3) : dailyQueue.slice(0, 3);

  return `<div class="dashboard-page" data-page="dashboard">
    <section class="page-intro">
      <div><div class="eyebrow"><span class="eyebrow-dot"></span>学习工作台 · ${escapeHtml(formatDate(new Date(), { weekday: "long" }))}</div><h1 class="page-title">今天，把知识取出来。</h1><p class="page-copy">从到期复习开始，再补几道新题。每一次主动回忆都会更新你的个人复习节奏。</p></div>
      <div class="page-actions"><button class="button secondary" type="button" data-action="start-weak">${icon("trend")}薄弱项</button><button class="button primary" type="button" data-action="start-daily">${icon("arrowRight")}开始今日训练</button></div>
    </section>
    <section class="metric-row" aria-label="学习概览">
      ${renderMetric("", "今日完成", `${todayCount} <small>/ ${goal}</small>`, todayCount >= goal ? "已完成" : `还差 ${Math.max(0, goal - todayCount)} 题`, todayCount >= goal ? "" : "muted")}
      ${renderMetric("amber", "连续学习", `${getStreak()} <small>天</small>`, getStreak() ? "保持节奏" : "完成一题即开始", "muted")}
      ${renderMetric("blue", "已掌握题目", formatNumber(mastered), mastered ? "持续累积" : "尚未建立", "muted")}
      ${renderMetric("coral", "待复习", formatNumber(getDueCount()), getDueCount() ? "今天到期" : "队列为空", getDueCount() ? "" : "muted")}
    </section>
    <section class="dashboard-grid">
      <section class="surface plan-surface" aria-labelledby="todayPlanTitle">
        <div class="surface-head"><div><div class="section-kicker">Next up</div><h2 class="section-title" id="todayPlanTitle">今日训练计划</h2><p class="section-subtitle">到期题优先，其次补充未练习题。</p></div><button class="surface-action" type="button" data-action="open-library">查看全部题库 ${icon("arrowUpRight")}</button></div>
        <div class="plan-summary"><div class="plan-number">${todayCount}<small>/ ${goal}</small></div><div><p>今日进度 · ${progressPercent}%</p><div class="progress-track"><i style="width:${progressPercent}%"></i></div></div><button class="button" type="button" data-action="start-daily">继续</button></div>
        <div class="queue-tabs" role="tablist"><button class="queue-tab ${state.dashboardTab === "today" ? "is-active" : ""}" type="button" data-action="dashboard-tab" data-tab="today">今日计划 <b>${dailyQueue.length}</b></button><button class="queue-tab ${state.dashboardTab === "review" ? "is-active" : ""}" type="button" data-action="dashboard-tab" data-tab="review">到期复习 <b>${reviewQueue.length}</b></button></div>
        <div class="queue-list">${renderQueueRows(activeQueue, state.dashboardTab === "review" ? "现在没有到期复习，先练几道新题吧。" : "今日计划已完成，去题库挑一道新的。")}</div>
        <div class="queue-footer"><span>当前题库 · ${formatNumber(state.catalog.stats.questionCount)} 道题</span><button type="button" data-action="shuffle-daily">换一组 ${icon("shuffle")}</button></div>
      </section>
      <aside class="insight-column" aria-label="学习洞察">
        <section class="surface dark-surface insight-panel"><div class="section-kicker">Skill map</div><h2 class="section-title">知识域掌握度</h2><p class="section-subtitle">根据每次自评和复习间隔更新。</p><div class="mastery-list">${renderMasteryRows()}</div><div class="insight-foot"><span>已覆盖知识域</span><b>${domainCount} 个 · ${formatNumber(state.catalog.stats.questionCount)} 题</b></div></section>
        <section class="surface insight-panel"><div class="section-kicker">Focus next</div><h2 class="section-title">建议优先处理</h2><p class="section-subtitle">把注意力留给最容易遗忘的内容。</p><div class="focus-list">${focus.length ? focus.map((question) => `<button class="focus-row" type="button" data-action="open-question" data-id="${escapeHtml(question.id)}"><span>${escapeHtml(question.title)}</span><b>${statusLabel(getQuestionStatus(question.id))}</b></button>`).join("") : `<div class="report-empty">完成第一道题后，这里会出现你的薄弱项。</div>`}</div></section>
      </aside>
    </section>
  </div>`;
}

function renderSessionRail() {
  const practice = state.practice;
  const items = practice.queue.map((id, index) => {
    const question = state.catalogMap.get(id);
    const complete = practice.completed.some((item) => item.id === id);
    return `<button class="session-item ${index === practice.index ? "is-active" : ""} ${complete ? "is-complete" : ""}" type="button" data-action="jump-session" data-index="${index}"><b>${complete ? icon("check") : String(index + 1).padStart(2, "0")}</b><span>${escapeHtml(question?.title || "加载题目…")}</span></button>`;
  }).join("");
  return `<aside class="session-rail"><div class="session-rail-head"><span>${escapeHtml(practice.label || "训练会话")}</span><b>${practice.index + 1}/${practice.queue.length}</b></div><div class="session-queue">${items}</div><div class="session-rule"></div><p class="session-tip">先在脑中组织答案，再查看参考答案。完成后选择记忆程度，系统会安排下一次复习。</p></aside>`;
}

function renderPracticeQuestion(question) {
  const practice = state.practice;
  const answer = question.answer || {};
  const reference = answer.referenceAnswer || "";
  const attachment = question.source?.unparsedAttachment;
  const canRate = practice.revealed;
  const hints = Array.isArray(question.hints) ? question.hints : [];
  const keyPoints = Array.isArray(answer.keyPoints) ? answer.keyPoints : [];
  const referenceContent = attachment
    ? `<div class="attachment-notice">该条目来自 PDF/附件，原文尚未解析。可以打开来源页补录答案，再用“不会 / 模糊 / 记得”记录当前状态。${question.source?.url ? ` <a href="${safeUrl(question.source.url)}" target="_blank" rel="noreferrer">打开来源 ${icon("external")}</a>` : ""}</div>`
    : `<div class="reference-body">${renderParagraphs(reference)}</div>${keyPoints.length ? `<ul class="key-points">${keyPoints.map((point) => `<li>${escapeHtml(point)}</li>`).join("")}</ul>` : ""}`;

  return `<article class="question-workspace">
    <div class="question-meta"><span class="meta-pill">${escapeHtml(question.primaryModule?.label || question.primaryModuleLabel || question.category || question.rootCategory)}</span><span>${escapeHtml((question.secondaryModules || []).slice(0, 2).map((module) => module.label).join(" · ") || question.sourceCategory || "待复核")}</span><span>·</span><span>${question.estimatedMinutes || 8} 分钟</span><span>·</span><span>${difficultyLabel(question.difficulty)}</span></div>
    <div class="question-number">Question ${String(practice.index + 1).padStart(2, "0")}</div>
    <h1 class="question-title">${escapeHtml(question.title)}</h1>
    <p class="question-summary">${escapeHtml(question.summary || "先用自己的话回答，再对照参考答案检查覆盖面、工程细节和边界条件。")}</p>
    <div class="answer-composer">
      <div class="composer-head"><span class="composer-label">你的回答</span><span class="composer-hint">建议先口述，再用关键词补全</span></div>
      <textarea class="answer-input" id="answerDraft" placeholder="把你在面试中会说的话写下来……">${escapeHtml(practice.draft || "")}</textarea>
      <div class="composer-actions"><div class="composer-actions-left"><button class="text-action" type="button" data-action="toggle-hint">${icon("spark")}${practice.showHint ? "收起提示" : "给我一个提示"}</button><button class="text-action" type="button" data-action="skip-question">跳过这题 ${icon("arrowRight")}</button></div><button class="button primary" type="button" data-action="show-answer" ${practice.revealed ? "disabled" : ""}>${practice.revealed ? "已展开参考答案" : "查看参考答案"} ${icon("arrowRight")}</button></div>
      ${practice.showHint && hints.length ? `<div class="hint-box">${hints.map((hint) => escapeHtml(hint)).join("<br />")}</div>` : practice.showHint ? `<div class="hint-box">从题目考察的核心概念、工程链路和失败边界三个层次组织答案。</div>` : ""}
    </div>
    ${practice.revealed ? `<section class="reference-answer"><div class="reference-head"><span class="reference-label">参考答案</span>${question.source?.url ? `<a class="reference-source" href="${safeUrl(question.source.url)}" target="_blank" rel="noreferrer">查看来源 ${icon("external")}</a>` : ""}</div>${referenceContent}</section>` : ""}
    <div class="rating-area"><div class="rating-copy"><strong>这道题现在掌握得怎么样？</strong><span>系统会根据你的选择安排下一次复习。快捷键：1 不会 · 2 模糊 · 3 记得</span></div><div class="rating-buttons"><button class="rating-button unknown" type="button" data-action="rate-question" data-rating="unknown" ${canRate ? "" : "disabled"}>不会</button><button class="rating-button unsure" type="button" data-action="rate-question" data-rating="unsure" ${canRate ? "" : "disabled"}>模糊</button><button class="rating-button remember" type="button" data-action="rate-question" data-rating="remember" ${canRate ? "" : "disabled"}>记得</button></div></div>
  </article>`;
}

function renderPractice() {
  if (!state.practice) {
    return `<div class="practice-page"><section class="surface practice-done"><div class="done-mark">${icon("play")}</div><h1>准备开始一轮训练</h1><p>系统会优先安排到期复习，再从题库里补充新题。</p><div class="page-actions" style="justify-content:center;margin-top:25px"><button class="button primary" type="button" data-action="start-daily">开始今日训练 ${icon("arrowRight")}</button><button class="button secondary" type="button" data-action="open-library">浏览题库</button></div></section></div>`;
  }
  const practice = state.practice;
  const progressPercent = Math.round((practice.index / Math.max(1, practice.queue.length)) * 100);
  if (practice.done) return renderPracticeDone();
  return `<div class="practice-page"><div class="practice-toolbar"><div class="practice-toolbar-left"><button class="back-link" type="button" data-action="back-dashboard">${icon("arrowLeft")}退出训练</button><span class="practice-session-label">${escapeHtml(practice.label || "训练会话")}</span></div><span class="practice-counter">已完成 ${practice.completed.length} / ${practice.queue.length}</span></div><div class="practice-progress"><i style="width:${progressPercent}%"></i></div><div class="practice-grid">${renderSessionRail()}${practice.loading ? `<article class="surface practice-loading">正在加载题目内容…</article>` : practice.current ? renderPracticeQuestion(practice.current) : `<article class="surface practice-loading">题目加载失败，请稍后重试。</article>`}</div></div>`;
}

function renderPracticeDone() {
  const results = state.practice.completed;
  const remembered = results.filter((item) => item.rating === "remember").length;
  const unsure = results.filter((item) => item.rating === "unsure").length;
  return `<div class="practice-page"><div class="practice-toolbar"><div class="practice-toolbar-left"><button class="back-link" type="button" data-action="back-dashboard">${icon("arrowLeft")}返回今日训练</button><span class="practice-session-label">${escapeHtml(state.practice.label || "训练会话")}</span></div></div><section class="surface practice-done"><div class="done-mark">${icon("check")}</div><h1>这一轮完成了。</h1><p>不错，记忆强度已经记录。下一次复习会按遗忘曲线自动安排。</p><div class="done-stats"><div class="done-stat"><strong>${results.length}</strong><span>完成题目</span></div><div class="done-stat"><strong>${remembered}</strong><span>记得</span></div><div class="done-stat"><strong>${unsure}</strong><span>需要巩固</span></div></div><div class="page-actions" style="justify-content:center"><button class="button primary" type="button" data-action="start-daily">再来一轮 ${icon("arrowRight")}</button><button class="button secondary" type="button" data-action="open-report">查看学习报告</button></div></section></div>`;
}

function getFilteredLibraryQuestions() {
  const { query, category, source, filter } = state.library;
  const normalized = query.trim().toLowerCase();
  return state.catalog.questions.filter((question) => {
    const searchableModules = [question.primaryModuleLabel, question.primaryModuleParentLabel, ...(question.secondaryModuleIds || []).map(moduleLabel)];
    const matchesQuery = !normalized || [question.title, question.summary, question.category, question.rootCategory, question.sourceCategory, question.sourceCollection, ...searchableModules, ...(question.tags || [])].join(" ").toLowerCase().includes(normalized);
    const matchesCategory = category === "all" || question.primaryModuleParentId === category;
    const matchesSource = source === "all" || question.sourceCollection === source;
    const status = getQuestionStatus(question.id);
    const matchesFilter = filter === "all" || (filter === "new" && status === "new") || (filter === "due" && status === "due") || (filter === "reviewed" && status !== "new");
    return matchesQuery && matchesCategory && matchesSource && matchesFilter;
  });
}

function renderLibrary() {
  const filtered = getFilteredLibraryQuestions();
  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  state.library.page = Math.min(state.library.page, pageCount);
  const start = (state.library.page - 1) * PAGE_SIZE;
  const visible = filtered.slice(start, start + PAGE_SIZE);
  const categoryOptions = state.catalog.categories.map((category) => `<option value="${escapeHtml(category.id)}" ${state.library.category === category.id ? "selected" : ""}>${escapeHtml(category.label)} · ${category.count}</option>`).join("");
  const sourceOptions = (state.catalog.source?.collections || []).map((source) => `<option value="${escapeHtml(source.id)}" ${state.library.source === source.id ? "selected" : ""}>${escapeHtml(source.label)} · ${source.questionCount}</option>`).join("");
  const pageButtons = Array.from({ length: Math.min(pageCount, 5) }, (_, index) => {
    const page = pageCount <= 5 ? index + 1 : Math.max(1, Math.min(pageCount - 4, state.library.page - 2)) + index;
    return `<button class="page-button ${page === state.library.page ? "is-current" : ""}" type="button" data-action="library-page" data-page="${page}">${page}</button>`;
  }).join("");

  return `<div class="library-page"><section class="page-intro"><div><div class="eyebrow"><span class="eyebrow-dot"></span>Knowledge library · ${formatNumber(state.catalog.stats.questionCount)} questions</div><h1 class="page-title">从知识模块里挑选训练。</h1><p class="page-copy">先按知识域筛选，再用来源、状态和关键词缩小范围。点击题目即可进入一次完整的回答—对照—复习流程。</p></div><div class="page-actions"><button class="button primary" type="button" data-action="start-random">${icon("shuffle")}随机挑战</button></div></section><div class="library-toolbar"><div class="filter-group"><span class="filter-label">状态</span><button class="filter-button ${state.library.filter === "all" ? "is-active" : ""}" type="button" data-action="library-filter" data-filter="all">全部</button><button class="filter-button ${state.library.filter === "new" ? "is-active" : ""}" type="button" data-action="library-filter" data-filter="new">未开始</button><button class="filter-button ${state.library.filter === "due" ? "is-active" : ""}" type="button" data-action="library-filter" data-filter="due">待复习</button><button class="filter-button ${state.library.filter === "reviewed" ? "is-active" : ""}" type="button" data-action="library-filter" data-filter="reviewed">已练习</button></div><select class="select-control" id="libraryCategory" aria-label="筛选知识域"><option value="all" ${state.library.category === "all" ? "selected" : ""}>全部知识域 · ${formatNumber(state.catalog.stats.questionCount)}</option>${categoryOptions}</select><select class="select-control" id="librarySource" aria-label="筛选来源"><option value="all" ${state.library.source === "all" ? "selected" : ""}>全部来源</option>${sourceOptions}</select><label class="library-search" for="librarySearch"><span class="icon icon-search"></span><input id="librarySearch" type="search" value="${escapeHtml(state.library.query)}" placeholder="搜索题目、知识模块或知识点" autocomplete="off" /></label></div><section class="library-table"><div class="library-table-head"><span>题目</span><span>知识模块</span><span>题型</span><span>状态</span></div>${visible.length ? visible.map((question) => { const status = getQuestionStatus(question.id); const reviewLabel = question.taxonomy?.status === "review" ? " · 待复核" : ""; return `<button class="library-row" type="button" data-action="open-question" data-id="${escapeHtml(question.id)}"><span><strong class="library-row-title">${escapeHtml(question.title)}</strong><small class="library-row-sub">${escapeHtml(question.summary || "面试口述题 · 先回答再复习")}</small></span><span class="library-category"><strong>${escapeHtml(question.primaryModuleLabel || "待复核")}</strong><small>${escapeHtml(`${question.sourceCategory || ""}${reviewLabel}`)}</small></span><span class="library-type">${question.type === "short_answer" ? "简答题" : escapeHtml(question.type)}</span><span class="status-tag library-status ${statusClass(status)}">${statusLabel(status)}</span></button>`; }).join("") : `<div class="library-empty">没有找到匹配题目。换一个关键词，或清除筛选条件。</div>`}<div class="library-bottom"><span>显示 ${filtered.length ? start + 1 : 0}–${Math.min(start + PAGE_SIZE, filtered.length)} / ${formatNumber(filtered.length)} 道</span><div class="pagination"><button class="page-button" type="button" data-action="library-page" data-page="${state.library.page - 1}" ${state.library.page <= 1 ? "disabled" : ""}>‹</button>${pageButtons}<button class="page-button" type="button" data-action="library-page" data-page="${state.library.page + 1}" ${state.library.page >= pageCount ? "disabled" : ""}>›</button></div></div></section></div>`;
}

function activityDays(count = 14) {
  return Array.from({ length: count }, (_, index) => {
    const date = new Date();
    date.setDate(date.getDate() - (count - index - 1));
    const day = todayKey(date);
    return { day, label: new Intl.DateTimeFormat("zh-CN", { weekday: "short" }).format(date), count: getAttemptsForDay(day).length };
  });
}

function renderReport() {
  const attempts = state.progress.attempts;
  const accuracy = getAccuracy(attempts);
  const days = activityDays();
  const maxActivity = Math.max(1, ...days.map((day) => day.count));
  const categories = state.catalog.categories.map((category) => ({ ...category, mastery: categoryMastery(category.id) })).sort((a, b) => (a.mastery.value - b.mastery.value) || (b.mastery.reviewed - a.mastery.reviewed));
  const recent = [...attempts].sort((a, b) => new Date(b.reviewedAt) - new Date(a.reviewedAt)).slice(0, 6);
  const questionTitle = (id) => state.catalogMap.get(id)?.title || "已移除的题目";
  const ratingLabel = { remember: "记得", unsure: "模糊", unknown: "不会" };
  return `<div class="report-page"><section class="page-intro"><div><div class="eyebrow"><span class="eyebrow-dot"></span>Learning report · local progress</div><h1 class="page-title">看见你的学习轨迹。</h1><p class="page-copy">这里记录真实的答题事件和复习节奏，不用虚构完成数。数据保存在当前浏览器中。</p></div><div class="page-actions"><button class="button secondary" type="button" data-action="start-daily">继续训练 ${icon("arrowRight")}</button></div></section><section class="report-grid"><section class="surface report-panel"><div class="report-header-line"><div><div class="section-kicker">Total reviews</div><h2 class="section-title">累计答题</h2></div><div class="report-number">${formatNumber(attempts.length)}<small>次</small></div></div><div class="chart-wrap"><div class="activity-chart">${days.map((day) => `<div class="activity-day" title="${day.day} · ${day.count} 次"><i class="activity-bar ${day.count ? "is-active" : ""}" style="height:${Math.max(3, Math.round(day.count / maxActivity * 100))}%"></i></div>`).join("")}</div><div class="activity-labels">${days.map((day) => `<span>${escapeHtml(day.label)}</span>`).join("")}</div><div class="legend"><span><i></i>有答题记录</span><span><i class="muted"></i>未记录</span></div></div></section><section class="surface report-panel"><div class="section-kicker">Retention</div><h2 class="section-title">记忆保留率</h2><p class="section-subtitle">按“记得”自评的答题比例计算。</p><div class="report-number" style="margin-top:22px">${accuracy === null ? "—" : `${accuracy}%`}<small>${attempts.length ? "全部答题" : "完成第一题后生成"}</small></div><div class="report-method"><span class="method-number">1</span><div><strong>先回忆，再查看</strong><p>把参考答案延后到主动回忆结束，减少“看懂了却说不出”的错觉。</p></div></div><div class="report-method"><span class="method-number">2</span><div><strong>按记忆程度评分</strong><p>不会、模糊、记得分别对应不同间隔，系统自动计算下一次复习时间。</p></div></div></section><section class="surface report-panel report-wide"><div class="report-header-line"><div><div class="section-kicker">Skill map</div><h2 class="section-title">知识域掌握度</h2><p class="section-subtitle">按知识域内已练习题目的平均掌握度排序。</p></div><span class="status-tag">${formatNumber(state.catalog.stats.domainCount || state.catalog.stats.categoryCount)} 个知识域</span></div><div class="mastery-table">${categories.slice(0, 10).map((category) => `<div class="mastery-table-row"><span title="${escapeHtml(category.label)}">${escapeHtml(category.label)} <small style="color:var(--muted)">· ${category.mastery.reviewed}/${category.count}</small></span><b>${category.mastery.reviewed ? `${category.mastery.value}%` : "新"}</b><div class="mini-track"><i style="width:${category.mastery.value}%"></i></div></div>`).join("")}</div></section><section class="surface report-panel report-wide"><div class="section-kicker">Recent activity</div><h2 class="section-title">最近的答题记录</h2>${recent.length ? `<div class="recent-list">${recent.map((attempt) => `<div class="recent-row"><span class="recent-mark ${attempt.rating}">${attempt.rating === "remember" ? "✓" : attempt.rating === "unsure" ? "~" : "×"}</span><span><strong class="recent-title">${escapeHtml(questionTitle(attempt.questionId))}</strong><small class="recent-meta">${escapeHtml(ratingLabel[attempt.rating] || "已记录")} · ${escapeHtml(attempt.day)}</small></span><time class="recent-time">${new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric" }).format(new Date(attempt.reviewedAt))}</time></div>`).join("")}</div>` : `<div class="report-empty">还没有答题记录。开始一轮训练，报告会从第一道题开始长出来。</div>`}</section></section></div>`;
}

function renderView() {
  if (!state.catalog) {
    appView.innerHTML = `<div class="loading-state"><div><div class="skeleton" style="width:180px;height:12px;margin:0 auto 14px"></div><div class="skeleton" style="width:320px;height:42px;margin:0 auto 10px"></div><div class="skeleton" style="width:260px;height:10px;margin:auto"></div></div></div>`;
    return;
  }
  updateShell();
  appView.innerHTML = state.view === "dashboard" ? renderDashboard() : state.view === "practice" ? renderPractice() : state.view === "library" ? renderLibrary() : renderReport();
}

function navigate(view) {
  if (!(view in VIEW_LABELS)) view = "dashboard";
  state.view = view;
  window.history.replaceState({}, "", `#${view}`);
  renderView();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function beginPractice(questionIds, label = "训练会话") {
  const questions = questionIds.map((item) => typeof item === "string" ? state.catalogMap.get(item) : item).filter(Boolean);
  const ids = uniqueQuestions(questions).map((question) => question.id);
  if (!ids.length) {
    showToast("当前没有可练习的题目。", "error");
    return;
  }
  state.practice = { queue: ids, index: 0, label, completed: [], current: null, loading: true, revealed: false, showHint: false, draft: "", done: false };
  navigate("practice");
  loadCurrentPracticeQuestion();
}

async function loadCurrentPracticeQuestion() {
  if (!state.practice || state.practice.done) return;
  const expectedId = state.practice.queue[state.practice.index];
  state.practice.loading = true;
  state.practice.current = null;
  state.practice.revealed = false;
  state.practice.showHint = false;
  state.practice.draft = state.progress.drafts[expectedId] || "";
  renderView();
  try {
    const question = await loadQuestion(expectedId);
    if (!state.practice || state.practice.queue[state.practice.index] !== expectedId) return;
    state.practice.current = question;
    state.practice.loading = false;
    renderView();
  } catch (error) {
    console.error(error);
    if (state.practice && state.practice.queue[state.practice.index] === expectedId) {
      state.practice.loading = false;
      renderView();
      showToast("题目内容加载失败，请检查网络或稍后重试。", "error");
    }
  }
}

function recordRating(rating) {
  const practice = state.practice;
  const question = practice?.current;
  if (!practice || !question || !practice.revealed) return;
  const reviewedAt = new Date().toISOString();
  const attempt = { questionId: question.id, day: todayKey(), reviewedAt, rating, answerLength: (practice.draft || "").trim().length };
  state.progress.attempts.push(attempt);
  updateSchedule(state.progress, question.id, rating, reviewedAt);
  delete state.progress.drafts[question.id];
  saveProgress();
  practice.completed.push({ id: question.id, rating });
  if (practice.index >= practice.queue.length - 1) {
    practice.done = true;
    practice.current = null;
    renderView();
    return;
  }
  practice.index += 1;
  loadCurrentPracticeQuestion();
}

function handleClick(event) {
  const viewButton = event.target.closest("[data-view]");
  if (viewButton) {
    const view = viewButton.dataset.view;
    if (view === "practice") {
      if (state.practice && !state.practice.done) navigate("practice");
      else beginPractice(getDailyQueue(), "今日训练");
    } else navigate(view);
    appShell.classList.remove("sidebar-open");
    return;
  }

  const actionElement = event.target.closest("[data-action]");
  if (!actionElement) return;
  const action = actionElement.dataset.action;
  if (action === "toggle-sidebar") appShell.classList.toggle("sidebar-open");
  if (action === "start-daily") beginPractice(getDailyQueue(), "今日训练");
  if (action === "start-weak") beginPractice(getWeakQueue(), "薄弱项强化");
  if (action === "start-random") {
    const seed = `${todayKey()}-${Math.random()}`;
    const random = [...state.catalog.questions].filter((question) => question.hasReferenceAnswer).sort((a, b) => stableHash(`${a.id}-${seed}`) - stableHash(`${b.id}-${seed}`)).slice(0, DAILY_GOAL);
    beginPractice(random.map((question) => question.id), "随机挑战");
  }
  if (action === "open-library") navigate("library");
  if (action === "open-report") navigate("report");
  if (action === "back-dashboard") navigate("dashboard");
  if (action === "profile") showToast("账号同步还未开启；当前进度只保存在本地浏览器。");
  if (action === "dashboard-tab") { state.dashboardTab = actionElement.dataset.tab; renderView(); }
  if (action === "shuffle-daily") { state.dashboardTab = "today"; beginPractice(getDailyQueue(), "换一组训练"); }
  if (action === "open-question") beginPractice([actionElement.dataset.id], "单题训练");
  if (action === "show-answer" && state.practice) { state.practice.revealed = true; renderView(); }
  if (action === "toggle-hint" && state.practice) { state.practice.showHint = !state.practice.showHint; renderView(); }
  if (action === "skip-question" && state.practice) {
    if (state.practice.index >= state.practice.queue.length - 1) { state.practice.done = true; renderView(); }
    else { state.practice.index += 1; loadCurrentPracticeQuestion(); }
  }
  if (action === "rate-question") recordRating(actionElement.dataset.rating);
  if (action === "jump-session" && state.practice) {
    const index = Number(actionElement.dataset.index);
    if (Number.isInteger(index) && index >= 0 && index < state.practice.queue.length) { state.practice.index = index; loadCurrentPracticeQuestion(); }
  }
  if (action === "library-filter") { state.library.filter = actionElement.dataset.filter; state.library.page = 1; renderView(); }
  if (action === "library-page") {
    const page = Number(actionElement.dataset.page);
    if (page > 0) { state.library.page = page; renderView(); }
  }
  if (action === "reset-progress") {
    if (window.confirm("确定要清空当前浏览器中的所有答题记录和复习计划吗？题库内容不会被删除。")) {
      state.progress = emptyProgress();
      saveProgress();
      state.practice = null;
      renderView();
      showToast("本地学习进度已清空。");
    }
  }
}

function handleInput(event) {
  if (event.target.id === "answerDraft" && state.practice?.current) {
    state.practice.draft = event.target.value;
    state.progress.drafts[state.practice.current.id] = event.target.value;
    saveProgress();
  }
  if (event.target.id === "globalSearch") return;
  if (event.target.id === "librarySearch") {
    state.library.query = event.target.value;
    state.library.page = 1;
    renderView();
    const input = document.getElementById("librarySearch");
    if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
  }
}

function handleChange(event) {
  if (event.target.id === "libraryCategory") {
    state.library.category = event.target.value;
    state.library.page = 1;
    renderView();
  }
  if (event.target.id === "librarySource") {
    state.library.source = event.target.value;
    state.library.page = 1;
    renderView();
  }
}

function handleKeydown(event) {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    document.getElementById("globalSearch")?.focus();
  }
  if (event.key === "Enter" && document.activeElement?.id === "globalSearch") {
    event.preventDefault();
    state.library.query = document.activeElement.value.trim();
    state.library.page = 1;
    navigate("library");
    const input = document.getElementById("librarySearch");
    if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
  }
  if (state.view !== "practice" || !state.practice?.current || !state.practice.revealed || ["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) return;
  const rating = { "1": "unknown", "2": "unsure", "3": "remember" }[event.key];
  if (rating) recordRating(rating);
}

async function boot() {
  document.addEventListener("click", handleClick);
  document.addEventListener("input", handleInput);
  document.addEventListener("change", handleChange);
  document.addEventListener("keydown", handleKeydown);
  window.addEventListener("hashchange", () => {
    const view = window.location.hash.slice(1);
    if (view in VIEW_LABELS) { state.view = view; renderView(); }
  });
  renderView();
  try {
    state.catalog = await fetchJson("catalog.json");
    state.catalogMap = new Map(state.catalog.questions.map((question) => [question.id, question]));
    state.moduleMap = new Map((state.catalog.knowledgeModules || []).map((module) => [module.id, module]));
    renderView();
  } catch (error) {
    console.error(error);
    appView.innerHTML = `<section class="error-state"><h2>题库加载失败</h2><p>请通过本地静态服务器打开页面（例如 <code>python -m http.server 8000</code>），或检查 data/catalog.json 是否存在。</p><button class="button primary" type="button" data-action="reload">重新加载</button></section>`;
  }
}

document.addEventListener("click", (event) => {
  if (event.target.closest('[data-action="reload"]')) window.location.reload();
});

boot();

// DayROAD 화면 — 공통 (엔진 요청 · 상태 · 날짜 · 아이콘 · 알림 · 떠 있는 창)
// made by. Nevertheless_D
'use strict';

const DR = (window.DR = window.DR || {});
const T = new URLSearchParams(location.search).get('t') || '';
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));

function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// ---------------------------------------------------------------- 엔진 요청

async function api(path, body, opts = {}) {
  const init = { method: body === undefined ? 'GET' : 'POST', headers: { 'x-token': T } };
  if (body !== undefined) { init.body = JSON.stringify(body); init.headers['content-type'] = 'application/json'; }
  let res;
  for (let i = 0; i < 3; i++) {
    try { res = await fetch(path, init); break; } catch (e) {
      if (i === 2 || opts.noRetry) throw new Error('앱 엔진과 연결이 끊겼어요. 잠시 뒤 다시 시도해 주세요');
      await new Promise((r) => setTimeout(r, 600));
    }
  }
  let data = {};
  try { data = await res.json(); } catch (e) { /* 내용 없음 */ }
  if (!res.ok || data.ok === false) {
    const err = new Error(data.error || '문제가 생겼어요. 다시 시도해 주세요');
    err.status = res.status;
    throw err;
  }
  return data;
}

const clientErrs = [];
function logClient(msg) {
  clientErrs.push(String(msg).slice(0, 500));
  clearTimeout(logClient.t);
  logClient.t = setTimeout(() => { const items = clientErrs.splice(0); api('/api/clientlog', { items }).catch(() => {}); }, 800);
}
window.addEventListener('error', (e) => logClient(`${e.message} @ ${(e.filename || '').split('/').pop()}:${e.lineno}`));
window.addEventListener('unhandledrejection', (e) => logClient('promise: ' + (e.reason && (e.reason.stack || e.reason.message) || e.reason)));
DR.logClient = logClient;

// ---------------------------------------------------------------- 상태

const S = (DR.S = {
  view: 'today',      // today | week | due | repeat | someday | done | cat
  catId: null,
  viewDate: '',       // 오늘 화면에서 보고 있는 날짜
  weekOf: '',         // 이번 주 화면에서 보고 있는 주의 첫날
  sel: null,          // 고른 할 일
  tasks: [], cats: [], palette: {}, today: '', rev: 0,
  settings: { appearance: 'system', weekStart: 'mon', carryOver: true, morning: {}, dueRemind: {}, hiddenCals: [] },
  update: null,
  native: { on: false, events: '', reminders: '', notify: '' },
  calendars: [],      // 맥 캘린더 목록
  events: {},         // 날짜 → 일정
  catForm: null,      // 분류 추가/고치기 칸
});

DR.task = (id) => S.tasks.find((t) => t.id === id) || null;
DR.cat = (id) => S.cats.find((c) => c.id === id) || null;

// 엔진이 준 상태를 받아들여요. 바뀌기 전 할 일 목록은 동기화(캘린더 · 미리 알림)가 비교할 수 있게 넘겨요.
function applyState(r) {
  if (!r || !r.tasks) return;
  const prev = new Map(S.tasks.map((t) => [t.id, t]));
  const dayChanged = S.today && r.today !== S.today;
  S.tasks = r.tasks;
  S.cats = r.cats || [];
  S.palette = r.palette || S.palette;
  S.rev = r.rev;
  S.today = r.today;
  if (!S.viewDate || dayChanged) S.viewDate = S.today;
  if (!S.weekOf || dayChanged) S.weekOf = weekStart(S.today);
  if (S.sel && !DR.task(S.sel)) S.sel = null;
  if (S.view === 'cat' && !DR.cat(S.catId)) S.view = 'today';
  if (DR.afterState) DR.afterState(prev);
}
DR.applyState = applyState;

async function act(path, body) {
  try {
    const r = await api(path, body);
    applyState(r);
    DR.render();
    return r;
  } catch (e) {
    toastErr(e);
    if (e.status === 400) DR.reload();
    return null;
  }
}
DR.act = act;

DR.reload = async function reload() {
  try { applyState(await api('/api/state')); DR.render(); } catch (e) { /* 다음 번에 */ }
};

// ---------------------------------------------------------------- 날짜

const DOW = ['일', '월', '화', '수', '목', '금', '토'];
const pd = (s) => { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); };
const fd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const addDays = (s, n) => { const d = pd(s); d.setDate(d.getDate() + n); return fd(d); };
const daysBetween = (a, b) => Math.round((pd(b) - pd(a)) / 86400000);
function weekStart(s, ws = S.settings.weekStart) {
  const d = pd(s);
  const off = ws === 'sun' ? d.getDay() : (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - off);
  return fd(d);
}
function dow(s) { return DOW[pd(s).getDay()]; }
function md(s) { const d = pd(s); return `${d.getMonth() + 1}월 ${d.getDate()}일`; }
function mdShort(s) { const d = pd(s); return `${d.getMonth() + 1}/${d.getDate()}`; }
// 사람이 읽기 좋은 날짜: 오늘 · 내일 · 어제 · 11월 12일 (목)
function relDay(s, withDow = true) {
  if (!s) return '';
  const n = daysBetween(S.today, s);
  if (n === 0) return '오늘';
  if (n === 1) return '내일';
  if (n === -1) return '어제';
  if (n === 2) return '모레';
  return md(s) + (withDow ? ` (${dow(s)})` : '');
}
function dueInfo(t) {
  if (!t.due) return null;
  const n = daysBetween(S.today, t.due);
  const d = dow(t.due);
  if (n < 0) return { d: '마감 지남', short: `${mdShort(t.due)}까지였어요`, warn: true, n };
  if (n === 0) return { d: 'D-day', short: '오늘까지', warn: true, n };
  if (n === 1) return { d: 'D-1', short: '내일까지', warn: true, n };
  if (n < 7) return { d: `D-${n}`, short: `${d}요일까지`, warn: false, n };
  return { d: `D-${n}`, short: `${mdShort(t.due)}까지`, warn: false, n };
}
function weekLabel(ws) {
  const a = pd(ws), b = pd(addDays(ws, 6));
  const names = ['첫째', '둘째', '셋째', '넷째', '다섯째'];
  // 그 주의 목요일이 속한 달 기준으로 몇째 주인지 (달력 관례)
  const th = pd(addDays(ws, S.settings.weekStart === 'sun' ? 4 : 3));
  const n2 = Math.floor((th.getDate() - 1) / 7);
  const range = a.getMonth() === b.getMonth()
    ? `${a.getMonth() + 1}월 ${a.getDate()}일 – ${b.getDate()}일`
    : `${a.getMonth() + 1}월 ${a.getDate()}일 – ${b.getMonth() + 1}월 ${b.getDate()}일`;
  return { title: `${th.getMonth() + 1}월 ${names[n2] || ''} 주`, range };
}
function fmtTime(hm) {
  if (!hm) return '';
  const [h, m] = hm.split(':').map(Number);
  const ap = h < 12 ? '오전' : '오후';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${ap} ${h12}:${String(m).padStart(2, '0')}`;
}
Object.assign(DR, { DOW, pd, fd, addDays, daysBetween, weekStart, dow, md, mdShort, relDay, dueInfo, weekLabel, fmtTime });

// 할 일 정렬: 시간이 있는 일은 시간 순서로 먼저, 나머지는 만든 순서
function sortTasks(list) {
  return list.slice().sort((a, b) => {
    const ta = a.time || '99', tb = b.time || '99';
    if (ta !== tb) return ta < tb ? -1 : 1;
    return a.order - b.order;
  });
}
DR.sortTasks = sortTasks;

// ---------------------------------------------------------------- 아이콘

const I = (d, w = 18, extra = '') => `<svg width="${w}" height="${w}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"${extra}>${d}</svg>`;
const ICON = (DR.ICON = {
  sun: I('<circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"></path>'),
  cal: I('<rect x="3" y="5" width="18" height="16" rx="3"></rect><path d="M3 10h18M8 3v4M16 3v4"></path>'),
  cal15: I('<rect x="3" y="5" width="18" height="16" rx="3"></rect><path d="M3 10h18M8 3v4M16 3v4"></path>', 15),
  cal12: I('<rect x="3" y="5" width="18" height="16" rx="3"></rect><path d="M3 10h18"></path>', 12, ' stroke-width="2.4"'),
  clock: I('<circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path>'),
  repeat: I('<path d="M17 2l4 4-4 4"></path><path d="M3 11v-1a4 4 0 0 1 4-4h14"></path><path d="M7 22l-4-4 4-4"></path><path d="M21 13v1a4 4 0 0 1-4 4H3"></path>'),
  repeat13: I('<path d="M17 2l4 4-4 4"></path><path d="M3 11v-1a4 4 0 0 1 4-4h14"></path><path d="M7 22l-4-4 4-4"></path><path d="M21 13v1a4 4 0 0 1-4 4H3"></path>', 13, ' stroke-width="2.2"'),
  bell: I('<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"></path><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"></path>'),
  bell13: I('<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"></path><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"></path>', 13, ' stroke-width="2.2"'),
  list: I('<path d="M4 7h16M4 12h10M4 17h7"></path>'),
  check: I('<path d="M5 12l5 5L20 7"></path>'),
  tick: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--on-done)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5L20 7"></path></svg>',
  gear: I('<circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"></path>'),
  arrow: I('<path d="M5 12h14M13 6l6 6-6 6"></path>', 16, ' stroke-width="2.2"'),
  left: I('<path d="M15 6l-6 6 6 6"></path>'),
  right: I('<path d="M9 6l6 6-6 6"></path>'),
  x: I('<path d="M6 6l12 12M18 6 6 18"></path>', 16),
  dots: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.8"></circle><circle cx="12" cy="12" r="1.8"></circle><circle cx="19" cy="12" r="1.8"></circle></svg>',
  trash: I('<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"></path>', 17),
  star: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"></path></svg>',
  starO: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"></path></svg>',
  plus: I('<path d="M12 5v14M5 12h14"></path>', 16, ' stroke-width="2.2"'),
  logo: (n = 30) => `<svg width="${n}" height="${n}" viewBox="0 0 160 160" aria-hidden="true"><rect x="10" y="10" width="140" height="140" rx="34" fill="#D9572B"></rect><g transform="rotate(-6 80 82)"><rect x="40" y="34" width="80" height="96" rx="10" fill="#FFFDF8"></rect><rect x="52" y="52" width="16" height="16" rx="4" fill="#3F7D57"></rect><rect x="52" y="78" width="56" height="9" rx="4" fill="#1F2A37"></rect><rect x="52" y="100" width="44" height="9" rx="4" fill="#1F2A37"></rect></g></svg>`,
  logoBig: `<svg width="64" height="64" viewBox="0 0 160 160" aria-hidden="true"><rect x="10" y="10" width="140" height="140" rx="34" fill="#D9572B"></rect><g transform="rotate(-6 80 82)"><rect x="40" y="34" width="80" height="96" rx="10" fill="#FFFDF8"></rect><rect x="52" y="52" width="14" height="14" rx="4" fill="#3F7D57"></rect><path d="M55 59 l3 3 l6 -6" stroke="#FFFFFF" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"></path><rect x="72" y="56" width="36" height="6" rx="3" fill="#C9C1B2"></rect><rect x="52" y="76" width="14" height="14" rx="4" fill="none" stroke="#1F2A37" stroke-width="3"></rect><rect x="72" y="80" width="30" height="6" rx="3" fill="#1F2A37"></rect><rect x="52" y="100" width="14" height="14" rx="4" fill="none" stroke="#1F2A37" stroke-width="3"></rect><rect x="72" y="104" width="24" height="6" rx="3" fill="#1F2A37"></rect></g></svg>`,
});

const REPEAT_NAME = (DR.REPEAT_NAME = { daily: '매일', weekdays: '평일', weekly: '매주', monthly: '매달' });
const PALETTE_KEYS = (DR.PALETTE_KEYS = ['blue', 'orange', 'purple', 'green', 'teal', 'gold', 'pink', 'slate']);
const PALETTE_NAME = (DR.PALETTE_NAME = { blue: '파랑', orange: '주홍', purple: '보라', green: '초록', teal: '청록', gold: '황토', pink: '분홍', slate: '회색' });

// ---------------------------------------------------------------- 알림 (토스트)

function toast(msg, opts = {}) {
  const box = $('#toasts');
  const el = document.createElement('div');
  el.className = 'toast' + (opts.err ? ' err' : '');
  el.setAttribute('role', opts.err ? 'alert' : 'status');
  el.innerHTML = `<span>${esc(msg)}</span>`;
  if (opts.action) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = opts.action.label;
    b.onclick = () => { el.remove(); opts.action.run(); };
    el.appendChild(b);
  }
  box.appendChild(el);
  while (box.children.length > 3) box.firstChild.remove();
  setTimeout(() => el.remove(), opts.ms || (opts.action ? 6500 : 3200));
  return el;
}
function toastErr(e) { toast((e && e.message) || String(e), { err: true }); }
Object.assign(DR, { toast, toastErr });

// ---------------------------------------------------------------- 떠 있는 메뉴 · 창

let openPop = null;
function closePop() {
  if (openPop) { const p = openPop; openPop = null; p.el.remove(); if (p.onClose) p.onClose(); }
}
// pop: 기준 요소(또는 {x, y}) 아래에 작은 창을 띄워요
function pop(html, anchor, opts = {}) {
  closePop();
  const el = document.createElement('div');
  el.className = 'pop ' + (opts.cls || '');
  el.setAttribute('role', opts.role || 'menu');
  el.innerHTML = html;
  document.body.appendChild(el);
  const r = anchor.getBoundingClientRect ? anchor.getBoundingClientRect() : { left: anchor.x, right: anchor.x, top: anchor.y, bottom: anchor.y };
  const w = el.offsetWidth, h = el.offsetHeight;
  let x = opts.alignRight ? r.right - w : r.left;
  let y = r.bottom + 6;
  if (x + w > innerWidth - 8) x = innerWidth - w - 8;
  if (x < 8) x = 8;
  if (y + h > innerHeight - 8) y = Math.max(8, r.top - h - 6);
  el.style.left = x + 'px';
  el.style.top = y + 'px';
  openPop = { el, onClose: opts.onClose };
  const first = el.querySelector('button, input');
  if (first && opts.focus !== false) first.focus({ preventScroll: true });
  return el;
}
document.addEventListener('mousedown', (e) => { if (openPop && !openPop.el.contains(e.target)) closePop(); }, true);
window.addEventListener('blur', () => closePop());
window.addEventListener('resize', () => closePop());

// menu: [{label, run, danger, key}] 또는 '-' (구분선)
function menu(items, anchor, opts = {}) {
  const el = pop(items.map((it, i) => {
    if (it === '-') return '<hr>';
    if (it.head) return `<div class="ph">${esc(it.head)}</div>`;
    return `<button type="button" class="mi${it.danger ? ' danger' : ''}" role="menuitem" data-i="${i}">${it.icon || ''}<span>${esc(it.label)}</span>${it.key ? `<span class="k">${esc(it.key)}</span>` : ''}</button>`;
  }).join(''), anchor, opts);
  el.addEventListener('click', (e) => {
    const b = e.target.closest('[data-i]');
    if (!b) return;
    const it = items[+b.dataset.i];
    closePop();
    it.run();
  });
  el.addEventListener('keydown', (e) => {
    const bs = $$('.mi', el);
    const i = bs.indexOf(document.activeElement);
    if (e.key === 'ArrowDown') { e.preventDefault(); (bs[i + 1] || bs[0]).focus(); }
    if (e.key === 'ArrowUp') { e.preventDefault(); (bs[i - 1] || bs[bs.length - 1]).focus(); }
  });
  return el;
}

// pickDate: 달력 창. quick: [{label, value}] (value 가 객체면 그대로 돌려줘요)
function pickDate(anchor, value, onPick, quick = []) {
  let month = pd(value || S.today);
  month.setDate(1);
  const draw = () => {
    const first = new Date(month);
    const ws = S.settings.weekStart === 'sun' ? 0 : 1;
    const start = new Date(first);
    start.setDate(1 - ((first.getDay() - ws + 7) % 7));
    const heads = Array.from({ length: 7 }, (_, i) => DOW[(i + ws) % 7]);
    let cells = '';
    for (let i = 0; i < 42; i++) {
      const d = new Date(start);
      d.setDate(start.getDate() + i);
      const s = fd(d);
      const cls = [d.getMonth() !== month.getMonth() ? 'o' : '', s === S.today ? 'td' : '', s === value ? 'on' : ''].join(' ');
      cells += `<button type="button" class="${cls}" data-d="${s}" aria-label="${md(s)} ${dow(s)}요일">${d.getDate()}</button>`;
    }
    return `${quick.length ? `<div class="quickrow">${quick.map((q, i) => `<button type="button" data-q="${i}">${esc(q.label)}</button>`).join('')}</div>` : ''}
      <div class="mh"><button type="button" class="iconbtn" data-m="-1" aria-label="지난달">${ICON.left}</button><b>${month.getFullYear()}년 ${month.getMonth() + 1}월</b><button type="button" class="iconbtn" data-m="1" aria-label="다음 달">${ICON.right}</button></div>
      <div class="g">${heads.map((h) => `<span class="h">${h}</span>`).join('')}${cells}</div>`;
  };
  const el = pop(draw(), anchor, { cls: 'cal', role: 'dialog', focus: false });
  el.addEventListener('click', (e) => {
    const m = e.target.closest('[data-m]');
    if (m) { month.setMonth(month.getMonth() + +m.dataset.m); el.innerHTML = draw(); return; }
    const d = e.target.closest('[data-d]');
    if (d) { closePop(); onPick(d.dataset.d); return; }
    const q = e.target.closest('[data-q]');
    if (q) { closePop(); onPick(quick[+q.dataset.q].value); }
  });
}

function modal(html, opts = {}) {
  const wrap = document.createElement('div');
  wrap.className = 'modal';
  wrap.innerHTML = html;
  document.body.appendChild(wrap);
  const close = () => { wrap.remove(); document.removeEventListener('keydown', onKey, true); if (opts.onClose) opts.onClose(); };
  const onKey = (e) => { if (e.key === 'Escape' && !openPop) { e.stopPropagation(); close(); } };
  document.addEventListener('keydown', onKey, true);
  wrap.addEventListener('mousedown', (e) => { if (e.target === wrap) close(); });
  return { el: wrap, close };
}
Object.assign(DR, { pop, closePop, menu, pickDate, modal, isPopOpen: () => !!openPop });

// ---------------------------------------------------------------- 맥 앱(Swift)에게 부탁하기

const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dayroad;
S.native.on = !!bridge;
if (bridge || /DayROADShell/.test(navigator.userAgent)) document.documentElement.classList.add('native');
async function native(type, data = {}) {
  if (!bridge) throw new Error('맥 앱에서만 쓸 수 있어요');
  return bridge.postMessage({ type, ...data });
}
DR.native = native;
DR.hasNative = () => !!bridge;

// 맥 앱이 화면에 알려 주는 것: DR.onNative(name, data)
DR.nativeHandlers = {};
DR.onNative = function (name, data) {
  const h = DR.nativeHandlers[name];
  if (h) try { h(data || {}); } catch (e) { logClient('native ' + name + ': ' + e.message); }
};

function applyTheme() {
  const a = S.settings.appearance;
  if (a === 'light' || a === 'dark') document.documentElement.dataset.theme = a;
  else delete document.documentElement.dataset.theme;
  if (bridge) native('appearance', { value: a }).catch(() => {});
}
DR.applyTheme = applyTheme;

DR.catClass = (id) => { const c = DR.cat(id); return c ? 'c-' + c.color : ''; };

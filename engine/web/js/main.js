// DayROAD — 누르기 · 끌기 · 단축키 · 빠른 추가 · 시작
'use strict';

(function () {
  const S = DR.S;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  function setView(view, extra = {}) {
    S.view = view;
    Object.assign(S, extra);
    if (view === 'today' && !extra.viewDate) S.viewDate = S.today;
    if (view === 'week' && !extra.weekOf) S.weekOf = DR.weekStart(S.today);
    if (view === 'month' && !extra.monthOf) S.monthOf = S.today.slice(0, 8) + '01';
    DR.colAdd = null;
    DR.render();
    $('#main').scrollTop = 0;
  }
  DR.setView = setView;

  // 하루 · 한 주 · 한 달 사이를 오갈 때, 보던 날짜 근처를 그대로 보여 줘요
  function changeRange(r) {
    const cur = S.view === 'week' ? S.weekOf : S.view === 'month' ? S.monthOf : S.viewDate;
    const span = S.view === 'week' ? 6 : S.view === 'month' ? new Date(DR.pd(cur).getFullYear(), DR.pd(cur).getMonth() + 1, 0).getDate() - 1 : 0;
    const anchor = S.today >= cur && S.today <= DR.addDays(cur, span) ? S.today : cur;
    if (r === 'today') setView('today', { viewDate: anchor });
    else if (r === 'week') setView('week', { weekOf: DR.weekStart(anchor) });
    else setView('month', { monthOf: anchor.slice(0, 8) + '01' });
  }

  function startEdit(id) {
    S.sel = id;
    if (S.view === 'week' || S.view === 'month') {
      DR.render();
      setTimeout(() => { const t = $('#dTitle'); if (t) { t.focus(); t.select(); } }, 220);
      return;
    }
    DR.editing = id;
    DR.render();
  }
  DR.startEdit = startEdit;

  async function commitEdit(input, keep) {
    const id = input.dataset.edit;
    const t = DR.task(id);
    const v = input.value.replace(/\s+/g, ' ').trim();
    DR.editing = null;
    if (keep && t && v && v !== t.title) {
      await DR.act('/api/task/save', { task: { id, title: v } });
      DR.toast('이름을 고쳤어요');
    } else {
      DR.render();
    }
  }
  document.addEventListener('keydown', (e) => {
    const inp = e.target.closest && e.target.closest('[data-edit]');
    if (!inp) return;
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); inp.dataset.done = '1'; commitEdit(inp, true); }
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); inp.dataset.done = '1'; commitEdit(inp, false); }
  }, true);
  document.addEventListener('focusout', (e) => {
    const inp = e.target.closest && e.target.closest('[data-edit]');
    if (inp && !inp.dataset.done) { inp.dataset.done = '1'; commitEdit(inp, true); }
  });
  document.addEventListener('dblclick', (e) => {
    if (e.target.closest('input, textarea')) return;
    // 첫 번째 누름에서 화면을 다시 그려서, 두 번째 누름의 요소는 이미 화면에서 빠져 있을 수 있어요 → 그 요소의 할 일 번호로 찾아요
    const h = e.target.closest && e.target.closest('.row[data-id], .card[data-id], .pill[data-id], .mtask[data-id]');
    if (h && DR.task(h.dataset.id) && !e.target.closest('#detail, #side') && DR.editing !== h.dataset.id) { e.preventDefault(); startEdit(h.dataset.id); }
  });

  // 같은 할 일을 빠르게 두 번 누르면 이름 고치기 (누를 때 화면을 다시 그려서, 브라우저의 '더블클릭'을 믿지 않고 직접 셈)
  let lastClick = { id: null, at: 0 };
  function select(id) {
    const now = Date.now();
    if (lastClick.id === id && now - lastClick.at < 450) { lastClick = { id: null, at: 0 }; startEdit(id); return; }
    lastClick = { id, at: now };
    if (S.sel === id) return;
    S.sel = id;
    DR.render();
  }

  // ---------------------------------------------------------------- 빠른 추가

  const qi = $('#qInput');

  function taskFromText(text, ctx) {
    const p = DR.parseQuick(text, ctx);
    const t = { title: p.title };
    t.bucket = p.bucket || ctx.bucket || 'day';
    if (p.date) { t.bucket = 'day'; t.date = p.date; }
    else if (t.bucket === 'day') t.date = ctx.date || S.today;
    if (t.bucket === 'week') t.weekOf = p.weekOf || ctx.weekOf || DR.weekStart(S.today);
    if (p.repeat && t.bucket === 'someday') { t.bucket = 'day'; t.date = S.today; }
    for (const k of ['time', 'due', 'repeat', 'star']) if (p[k]) t[k] = p[k];
    if (p.cat || ctx.cat) t.cat = p.cat || ctx.cat;
    if (p.newCat) t._newCat = p.newCat;
    return t;
  }

  function placeName(t) {
    if (t.bucket === 'someday') return '언젠가';
    if (t.bucket === 'week') return t.weekOf === DR.weekStart(S.today) ? '이번 주 안에' : DR.md(t.weekOf) + ' 주';
    return DR.relDay(t.date);
  }

  function visibleHere(t) {
    switch (S.view) {
      case 'today': return t.bucket === 'day' && t.date === S.viewDate;
      case 'week': return DR.sel.inWeek(t, S.weekOf);
      case 'month': return t.bucket === 'day' && t.date.slice(0, 7) === S.monthOf.slice(0, 7);
      case 'someday': return t.bucket === 'someday';
      case 'cat': return t.cat === S.catId;
      case 'repeat': return !!t.repeat;
      case 'due': return !!t.due;
      default: return false;
    }
  }

  async function addFromText(text, ctx) {
    if (!text.trim()) return null;
    const t = taskFromText(text, ctx);
    if (t._newCat) {
      // "분류는 ○○," 에 없는 분류를 쓰면 새로 만들어요
      const used = new Set(S.cats.map((c) => c.color));
      const color = DR.PALETTE_KEYS.find((k) => !used.has(k)) || DR.PALETTE_KEYS[S.cats.length % DR.PALETTE_KEYS.length];
      const rc = await DR.act('/api/cat/save', { cat: { name: t._newCat, color } });
      if (rc && rc.cat) { t.cat = rc.cat.id; DR.toast(`새 분류를 만들었어요 · ${rc.cat.name}`); }
      delete t._newCat;
    }
    const r = await DR.act('/api/task/save', { task: t });
    if (!r || !r.task) return null;
    const nt = r.task;
    if (!visibleHere(nt)) {
      DR.toast(`${placeName(nt)}에 넣었어요 · ${nt.title}`, { action: { label: '보기', run: () => { goTo(nt); } } });
    }
    return nt;
  }

  function goTo(t) {
    if (t.bucket === 'someday') setView('someday', { sel: t.id });
    else if (t.bucket === 'week') setView('week', { weekOf: t.weekOf, sel: t.id });
    else setView('today', { viewDate: t.date, sel: t.id });
  }
  DR.goTo = goTo;

  DR.updateQuickChips = function () {
    const ctx = DR.quickCtx();
    const v = qi.value;
    const box = $('#qChips');
    qi.placeholder = S.view === 'week' ? `${ctx.hint} 할 일 — 예: 수요일 7시 요가, 금요일까지 보고서`
      : S.view === 'someday' ? '언젠가 하고 싶은 일 — 예: 제주도 여행 계획'
        : S.view === 'today' && S.viewDate !== S.today ? `${DR.relDay(S.viewDate)}에 할 일 — 예: 오후 3시 치과`
          : '할 일을 적고 Enter — 예: 금요일까지 보고서, 매주 월 9시 회의';
    if (!v.trim()) { box.innerHTML = ''; return; }
    const p = DR.parseQuick(v, ctx);
    box.innerHTML = p.chips.map((c) => `<span class="chip">${esc(c)}</span>`).join('');
  };

  qi.addEventListener('input', DR.updateQuickChips);
  qi.addEventListener('keydown', async (e) => {
    if (e.key === 'Enter' && !e.isComposing) {
      e.preventDefault();
      const v = qi.value;
      if (!v.trim()) return;
      qi.value = '';
      DR.updateQuickChips();
      const t = await addFromText(v, DR.quickCtx());
      if (!t) { qi.value = v; DR.updateQuickChips(); }
    }
    if (e.key === 'Escape') { qi.value = ''; DR.updateQuickChips(); qi.blur(); }
  });
  $('#qAdd').addEventListener('click', async () => {
    const v = qi.value;
    if (!v.trim()) { qi.focus(); return; }
    qi.value = '';
    DR.updateQuickChips();
    const t = await addFromText(v, DR.quickCtx());
    if (!t) qi.value = v;
    qi.focus();
  });

  // 이번 주 화면: 요일 칸 안에서 바로 적기
  document.addEventListener('keydown', async (e) => {
    const inp = e.target.closest && e.target.closest('[data-colin]');
    if (!inp) return;
    if (e.key === 'Escape') { DR.colAdd = null; DR.renderMain(); return; }
    if (e.key === 'Enter' && !e.isComposing) {
      e.preventDefault();
      const v = inp.value;
      if (!v.trim()) return;
      const where = inp.dataset.colin;
      inp.value = '';
      const ctx = where === 'week' ? { bucket: 'week', weekOf: S.weekOf } : { bucket: 'day', date: where };
      await addFromText(v, ctx);
    }
  });
  document.addEventListener('focusout', (e) => {
    const inp = e.target.closest && e.target.closest('[data-colin]');
    if (inp && !inp.value.trim()) setTimeout(() => { if (!document.activeElement || !document.activeElement.closest('[data-colin]')) { DR.colAdd = null; DR.renderMain(); } }, 120);
  });

  // ---------------------------------------------------------------- 누르기

  function taskMenu(anchor, t) {
    const items = [{ label: '이름 고치기', key: '더블클릭', run: () => startEdit(t.id) }, '-'];
    const today = S.today, tmr = DR.addDays(S.today, 1);
    if (!(t.bucket === 'day' && t.date === today)) items.push({ label: '오늘로', run: () => move(t.id, { bucket: 'day', date: today }) });
    if (!(t.bucket === 'day' && t.date === tmr)) items.push({ label: '내일로', run: () => move(t.id, { bucket: 'day', date: tmr }) });
    if (!(t.bucket === 'week' && t.weekOf === DR.weekStart(today))) items.push({ label: '이번 주 안에', run: () => move(t.id, { bucket: 'week', weekOf: DR.weekStart(today) }) });
    if (t.bucket !== 'someday') items.push({ label: '언젠가로', run: () => move(t.id, { bucket: 'someday' }) });
    items.push({ label: '날짜 고르기…', run: () => DR.whenMenu(anchor, t, (p) => move(t.id, p)) });
    items.push('-');
    items.push({ label: t.star ? '중요 표시 빼기' : '중요 표시', run: () => DR.act('/api/task/save', { task: { id: t.id, star: !t.star } }) });
    items.push({ label: '분류 바꾸기…', run: () => DR.catMenu(anchor, t) });
    items.push('-');
    items.push({ label: t.done ? '다시 할 일로' : '끝냈어요', key: 'Space', run: () => DR.toggle(t.id) });
    items.push({ label: '지우기', key: '⌫', danger: true, run: () => DR.deleteTask(t.id) });
    DR.menu(items, anchor);
  }

  async function move(id, patch) {
    const r = await DR.act('/api/task/save', { task: { id, ...patch } });
    if (r && r.task && !visibleHere(r.task)) DR.toast(`${placeName(r.task)} 칸으로 옮겼어요`, { action: { label: '보기', run: () => goTo(r.task) } });
  }

  async function onAct(e) {
    const b = e.target.closest('[data-act]');
    const holder = e.target.closest('[data-id]');
    if (!b) {
      if (holder && !e.target.closest('input, textarea') && (holder.classList.contains('row') || holder.classList.contains('card'))) select(holder.dataset.id);
      else if (!holder && S.sel && (S.view === 'week' || S.view === 'month') && e.currentTarget.id === 'main' && !e.target.closest('input, textarea, button, a')) { S.sel = null; DR.render(); }
      return;
    }
    const a = b.dataset.act;
    const id = holder && holder.dataset.id;
    switch (a) {
      case 'view': setView(b.dataset.view); break;
      case 'cat': setView('cat', { catId: b.dataset.id }); break;
      case 'cat-new': DR.openCatForm(); break;
      case 'cat-edit': DR.openCatForm(DR.cat(b.dataset.id)); break;
      case 'cat-cancel': S.catForm = null; DR.renderSide(); break;
      case 'cat-color': if (S.catForm) { S.catForm.name = ($('#catName') || {}).value || S.catForm.name; S.catForm.color = b.dataset.color; DR.renderSide(); } break;
      case 'settings': DR.openSettings(); break;
      case 'cal-connect': DR.calConnect(); break;
      case 'open-privacy': DR.openPrivacy(b.dataset.pane); break;
      case 'goto-day': setView('today', { viewDate: b.dataset.date }); break;
      case 'day-step': setView('today', { viewDate: DR.addDays(S.viewDate, +b.dataset.n) }); break;
      case 'week-step': S.weekOf = DR.addDays(S.weekOf, +b.dataset.n); DR.colAdd = null; DR.renderMain(); break;
      case 'week-this': S.weekOf = DR.weekStart(S.today); DR.renderMain(); break;
      case 'month-step': { const m = DR.pd(S.monthOf); m.setMonth(m.getMonth() + +b.dataset.n); S.monthOf = DR.fd(m); DR.renderMain(); break; }
      case 'month-this': S.monthOf = S.today.slice(0, 8) + '01'; DR.renderMain(); break;
      case 'range': changeRange(b.dataset.r); break;
      case 'toggle': if (id) DR.toggle(id); break;
      case 'select': if (id) select(id); break;
      case 'more': if (id) taskMenu(b, DR.task(id)); break;
      case 'col-add': DR.colAdd = b.dataset.date; DR.renderMain(); break;
      case 'restart': DR.restartApp(); break;
      case 'install': DR.installUpdate(); break;
    }
  }
  $('#main').addEventListener('click', onAct);
  $('#side').addEventListener('click', onAct);
  $('#detail').addEventListener('click', (e) => { const b = e.target.closest('[data-act]'); if (b) onAct(e); });
  $('#side').addEventListener('submit', (e) => { e.preventDefault(); DR.submitCatForm(); });
  $('#side').addEventListener('input', (e) => { if (e.target.id === 'catName' && S.catForm) S.catForm.name = e.target.value; });
  $('#side').addEventListener('keydown', (e) => { if (e.target.id === 'catName' && e.key === 'Escape') { S.catForm = null; DR.renderSide(); } });

  document.addEventListener('contextmenu', (e) => {
    if (e.target.closest('input, textarea')) return;
    const holder = e.target.closest('#main [data-id]');
    if (holder) { e.preventDefault(); select(holder.dataset.id); taskMenu({ x: e.clientX, y: e.clientY }, DR.task(holder.dataset.id)); return; }
    const cat = e.target.closest('#side [data-act="cat"]');
    if (cat) { e.preventDefault(); DR.catContext({ x: e.clientX, y: e.clientY }, cat.dataset.id); return; }
    e.preventDefault();
  });

  // ---------------------------------------------------------------- 끌어서 옮기기

  let dragId = null;
  document.addEventListener('dragstart', (e) => {
    const h = e.target.closest && e.target.closest('[data-id][draggable]');
    if (!h) return;
    dragId = h.dataset.id;
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', DR.task(dragId) ? DR.task(dragId).title : '');
    h.classList.add('dragging');
  });
  document.addEventListener('dragend', () => { dragId = null; $$('.dragging, .over').forEach((x) => x.classList.remove('dragging', 'over')); });
  const dropTarget = (el) => el.closest && el.closest('[data-drop-date], [data-drop-week], [data-drop-view]');
  document.addEventListener('dragover', (e) => {
    if (!dragId) return;
    const t = dropTarget(e.target);
    $$('.over').forEach((x) => { if (x !== t) x.classList.remove('over'); });
    if (!t) return;
    if (t.dataset.dropView && !['today', 'week', 'someday'].includes(t.dataset.dropView)) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    t.classList.add('over');
  });
  document.addEventListener('drop', (e) => {
    const t = dropTarget(e.target);
    if (!dragId || !t) return;
    e.preventDefault();
    const id = dragId;
    const task = DR.task(id);
    dragId = null;
    $$('.over, .dragging').forEach((x) => x.classList.remove('over', 'dragging'));
    let patch = null;
    if (t.dataset.dropDate) patch = { bucket: 'day', date: t.dataset.dropDate };
    else if (t.dataset.dropWeek) patch = { bucket: 'week', weekOf: t.dataset.dropWeek };
    else if (t.dataset.dropView === 'today') patch = { bucket: 'day', date: S.today };
    else if (t.dataset.dropView === 'week') patch = { bucket: 'week', weekOf: DR.weekStart(S.today) };
    else if (t.dataset.dropView === 'someday') patch = { bucket: 'someday' };
    if (!patch || !task) return;
    if (task.bucket === patch.bucket && (task.date || '') === (patch.date || task.date || '') && (task.weekOf || '') === (patch.weekOf || task.weekOf || '')) return;
    move(id, patch);
  });

  // ---------------------------------------------------------------- 단축키

  const typing = (el) => el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable);
  function visibleIds() { return $$('#mainBody [data-id]').map((x) => x.dataset.id); }

  document.addEventListener('keydown', (e) => {
    if (e.defaultPrevented) return;
    const mod = e.metaKey || e.ctrlKey;
    if (e.key === 'Escape') {
      if (DR.isPopOpen()) { DR.closePop(); return; }
      if (typing(e.target)) return;
      if (S.sel) { S.sel = null; DR.render(); }
      return;
    }
    if (mod && e.key.toLowerCase() === 'n') { e.preventDefault(); focusQuick(); return; }
    if (mod && e.key === ',') { e.preventDefault(); DR.openSettings(); return; }
    if (mod && !e.shiftKey && /^[1-7]$/.test(e.key)) { e.preventDefault(); setView(['today', 'week', 'month', 'due', 'repeat', 'someday', 'done'][+e.key - 1]); return; }
    if (typing(e.target) || document.querySelector('.modal')) return;
    if (mod && e.key.toLowerCase() === 'z' && DR.lastDeleted) { e.preventDefault(); DR.undoDelete(); return; }
    if (mod) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      const ids = visibleIds();
      if (!ids.length) return;
      e.preventDefault();
      const i = ids.indexOf(S.sel);
      const j = i < 0 ? 0 : Math.max(0, Math.min(ids.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)));
      select(ids[j]);
      const el = $(`#mainBody [data-id="${ids[j]}"]`);
      if (el) el.scrollIntoView({ block: 'nearest' });
      return;
    }
    if (!S.sel) return;
    if (e.key === ' ') { e.preventDefault(); DR.toggle(S.sel); }
    else if (e.key === 'Backspace' || e.key === 'Delete') { e.preventDefault(); DR.deleteTask(S.sel); }
    else if (e.key === 'Enter') { e.preventDefault(); const t = $('#dTitle'); if (t) { t.focus(); t.setSelectionRange(t.value.length, t.value.length); } }
  });

  function focusQuick() {
    if (S.view === 'done') setView('today');
    qi.focus();
  }

  // ---------------------------------------------------------------- 맥 앱 메뉴 · 위젯에서 열기

  DR.nativeHandlers.menu = ({ action }) => {
    if (action === 'new') focusQuick();
    else if (action === 'settings') DR.openSettings();
    else if (['today', 'week', 'month', 'due', 'repeat', 'someday', 'done'].includes(action)) setView(action);
  };
  DR.nativeHandlers.url = ({ url }) => {
    const u = String(url || '');
    const m = u.match(/^dayroad:\/\/task\/([\w-]+)/);
    if (m && DR.task(m[1])) { goTo(DR.task(m[1])); return; }
    if (u.startsWith('dayroad://week')) setView('week');
    else setView('today');
  };

  // ---------------------------------------------------------------- 엔진 확인 (5초마다)

  DR.poll = async function () {
    try {
      const r = await api('/api/poll', undefined, { noRetry: true });
      const before = S.update && S.update.status;
      S.update = r.update;
      if (r.rev !== S.rev || r.today !== S.today) await DR.reload();
      else if (before !== S.update.status) { DR.renderSide(); if (S.view === 'today') DR.renderMain(); }
      DR.drawSettings();
    } catch (e) { /* 조용히 */ }
  };

  // ---------------------------------------------------------------- 시작

  async function start() {
    try {
      S.settings = await api('/api/settings');
      DR.applyTheme();
      DR.applyState(await api('/api/state'));
    } catch (e) {
      document.getElementById('mainBody').innerHTML = `<div class="empty"><b>앱 엔진에 연결하지 못했어요</b>${esc(e.message)}</div>`;
      return;
    }
    await DR.refreshNative();
    const smoke = S.settings.ui && S.settings.ui.smoke;
    if (smoke) {
      if (smoke.view) S.view = smoke.view;
      if (smoke.sel) { const t = S.tasks.find((x) => x.title === smoke.sel) || S.tasks.find((x) => !x.done); if (t) S.sel = t.id; }
    }
    DR.render();
    if (smoke && smoke.settings) DR.openSettings();
    if (DR.syncAll) DR.syncAll();
    DR.pullReminders();
    DR.scheduleNotify(true);
    DR.poll();
    setInterval(DR.poll, 5000);
  }
  start();
})();

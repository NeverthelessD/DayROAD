// DayROAD — 오른쪽 '자세히' 칸 (날짜 · 시간 · 언제까지 · 알림 · 반복 · 캘린더 · 진행 기록)
'use strict';

(function () {
  const S = DR.S, ICON = DR.ICON;
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = (s, el = document) => el.querySelector(s);
  const FLAG = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 21V4M5 4h11l-2 4 2 4H5"></path></svg>';
  const TIME = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 7v5l3 2"></path></svg>';
  const DAY = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="3"></rect><path d="M3 10h18M8 3v4M16 3v4"></path></svg>';
  const BELL = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"></path><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"></path></svg>';
  const REP = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 2l4 4-4 4"></path><path d="M3 11v-1a4 4 0 0 1 4-4h14"></path><path d="M7 22l-4-4 4-4"></path><path d="M21 13v1a4 4 0 0 1-4 4H3"></path></svg>';

  function whenText(t) {
    if (t.bucket === 'someday') return '언젠가';
    if (t.bucket === 'week') return t.weekOf === DR.weekStart(S.today) ? '이번 주 안에' : `${DR.md(t.weekOf)} 주 안에`;
    return DR.relDay(t.date) + (Math.abs(DR.daysBetween(S.today, t.date)) <= 2 ? ` · ${DR.md(t.date)}` : '');
  }

  function emptyHTML() {
    return `<div class="dempty">${DR.ICON.logo(52)}<b>할 일을 눌러 보세요</b>여기에서 마감일 · 알림 · 반복을 정하고<br>어디까지 했는지 적어 둘 수 있어요.
      <div class="tips">
        <div><b>빨리 적기</b> — "내일 3시 치과", "금요일까지 보고서", "매주 월 9시 회의", "#공부 단어 외우기 !"</div>
        <div><b>단축키</b> — ⌘N 새 할 일 · ⌘1 오늘 · ⌘2 이번 주 · ⌘3 이번 달 · 두 번 누르기 이름 고치기 · 스페이스 끝내기 · ⌫ 지우기(고른 할 일이 없으면 뒤로) · ⌘Z 되돌리기 · 기록 두 번 누르기 고치기</div>
        <div><b>위젯</b> — 바탕화면을 오른쪽 클릭 › 위젯 편집 › DayROAD</div>
      </div></div>`;
  }

  function detailHTML(t) {
    const c = DR.cat(t.cat);
    const d = DR.dueInfo(t);
    const isDay = t.bucket === 'day';
    const reps = t.bucket === 'week' ? [['', '안 함'], ['weekly', '매주']] : [['', '안 함'], ['daily', '매일'], ['weekdays', '평일'], ['weekly', '매주'], ['monthly', '매달']];
    const calOk = S.native.events === 'full';
    let calRow = '';
    if (S.native.on && isDay) {
      const calName = (S.calendars.find((x) => x.id === S.settings.eventCalendar) || S.calendars.find((x) => x.isDefault) || {}).title || '기본 캘린더';
      calRow = `<div class="drow">${DAY}<span class="lab">캘린더에도 표시${calOk && t.calendar ? `<br><span style="font-size: 12px; color: var(--muted)">${esc(calName)}</span>` : ''}</span>
        ${calOk ? `<button type="button" class="switch" role="switch" aria-checked="${!!t.calendar}" aria-label="캘린더에도 표시" data-dact="calendar"><span></span></button>`
          : `<button type="button" class="btn sm" data-act="cal-connect">연결하기</button>`}</div>`;
    }
    const logs = t.log.map((l, i) => {
      const d = `<span class="d">${esc(DR.relDay(l.date, false))}</span>`;
      if (i === editingLog) {
        return `<div class="log editing">${d}<div class="lgedit">
          <label for="dLogEdit" class="sr">기록 고치기</label>
          <textarea id="dLogEdit" class="field" rows="2" data-i="${i}" spellcheck="false">${esc(l.text)}</textarea>
          <div class="lgbtns"><span class="hint">↩ 저장 · esc 취소</span><button type="button" class="btn sm" data-dact="logcancel">취소</button><button type="button" class="btn sm primary" data-dact="logsave" data-i="${i}">저장</button></div>
        </div></div>`;
      }
      return `<div class="log">${d}<span class="x" data-i="${i}" title="두 번 누르면 고칠 수 있어요">${esc(l.text)}${l.progress ? `<span class="p">${l.progress}%</span>` : ''}</span>
        <span class="acts"><button type="button" class="xbtn" data-dact="logedit" data-i="${i}" aria-label="기록 고치기" title="고치기">${ICON.pen}</button><button type="button" class="xbtn" data-dact="logdel" data-i="${i}" aria-label="기록 지우기" title="지우기">${ICON.x}</button></span></div>`;
    }).join('');
    return `
      <div class="dtop">
        <button type="button" class="catpick${c ? ' c-' + c.color : ''}" data-dact="cat"><span class="dot"></span>${c ? esc(c.name) : '분류 없음'} ▾</button>
        ${t.carriedFrom && !t.done ? `<span class="chip carry">${DR.mdShort(t.carriedFrom)}에서 넘어옴</span>` : ''}
        <span style="flex: 1"></span>
        <button type="button" class="iconbtn" data-dact="star" aria-pressed="${!!t.star}" aria-label="중요 표시" style="${t.star ? 'color: var(--accent)' : ''}">${t.star ? ICON.star : ICON.starO}</button>
        <button type="button" class="iconbtn" data-dact="delete" aria-label="지우기">${ICON.trash}</button>
        <button type="button" class="iconbtn dclose" data-dact="close" aria-label="닫기">${ICON.x}</button>
      </div>
      <label for="dTitle" class="sr">할 일 이름</label>
      <textarea id="dTitle" class="dtitle${t.done ? ' done' : ''}" rows="1" data-field="title" spellcheck="false" title="눌러서 이름을 고칠 수 있어요">${esc(t.title)}</textarea>
      <div class="dbox">
        <div class="drow">${DAY}<span class="lab">날짜</span><button type="button" class="vbtn" data-dact="date">${esc(whenText(t))}</button></div>
        ${isDay ? `<div class="drow">${TIME}<span class="lab">시간</span>
          <button type="button" class="vbtn${t.time ? '' : ' off'}" data-dact="time">${t.time ? DR.fmtTime(t.time) : '정하지 않음'}</button>
          ${t.time ? `<button type="button" class="xbtn" data-dact="clear" data-f="time" aria-label="시간 없애기" title="시간 없애기">${ICON.x}</button>` : ''}</div>` : ''}
        <div class="drow">${FLAG}<span class="lab">언제까지${d ? ` <span class="chip${d.warn ? ' warn' : ''}" style="margin-left: 4px">${d.d}</span>` : ''}</span>
          <button type="button" class="vbtn${t.due ? '' : ' off'}" data-dact="due">${t.due ? esc(DR.md(t.due) + ` (${DR.dow(t.due)})까지`) : '정하지 않음'}</button>
          ${t.due ? `<button type="button" class="xbtn" data-dact="clear" data-f="due" aria-label="마감 지우기">${ICON.x}</button>` : ''}</div>
        ${isDay ? `<div class="drow">${BELL}<span class="lab">알림</span>
          ${t.alarm ? `<button type="button" class="vbtn" data-dact="alarmtime" aria-label="알림 시각 바꾸기">${DR.fmtTime(t.alarm)}</button>` : ''}
          <button type="button" class="switch" role="switch" aria-checked="${!!t.alarm}" aria-label="알림" data-dact="alarm"><span></span></button></div>` : ''}
        ${t.bucket !== 'someday' ? `<div class="drow col2"><span class="lab">${REP}반복</span>
          <div class="repseg" role="radiogroup" aria-label="반복" style="grid-template-columns: repeat(${reps.length}, minmax(0, 1fr))">${reps.map(([v, l]) => `<button type="button" role="radio" aria-checked="${(t.repeat || '') === v}" data-dact="repeat" data-v="${v}">${l}</button>`).join('')}</div></div>` : ''}
        ${calRow}
      </div>

      <div style="display: flex; flex-direction: column; gap: 10px">
        <div class="ptop"><b>어디까지 했나요</b><span>${t.done ? '끝냄' : t.progress + '%'}</span></div>
        <div class="bar pbar"><i style="width: ${t.done ? 100 : t.progress}%"></i></div>
        <div class="pbtns" role="radiogroup" aria-label="진행 정도">${[0, 25, 50, 75, 100].map((v) => `<button type="button" role="radio" aria-checked="${t.progress === v}" data-dact="progress" data-v="${v}">${v}%</button>`).join('')}</div>
        <label for="dMemo" class="plabel">오늘 한 만큼 적어 두기</label>
        <textarea id="dMemo" class="field" rows="2" placeholder="예: 2장까지 씀, 표 정리만 남음" data-memo></textarea>
        <button type="button" class="btn" style="align-self: flex-end" data-dact="addlog">기록 남기기 <span style="color: var(--muted); font-size: 12px">⌘↩</span></button>
        ${logs ? `<div class="logs">${logs}</div>` : ''}
      </div>
      ${t.note ? `<div style="display: flex; flex-direction: column; gap: 6px"><label for="dNote" class="plabel">메모</label><textarea id="dNote" class="field" rows="3" data-field="note">${esc(t.note)}</textarea></div>` : ''}

      <div style="flex: 1"></div>
      <div class="dfoot">
        ${t.done ? '<button type="button" class="btn grow" data-dact="toggle">다시 할 일로</button>'
          : `<button type="button" class="btn good grow" data-dact="toggle">끝냈어요</button>${isDay ? '<button type="button" class="btn" data-dact="tomorrow">내일로 미루기</button>' : ''}`}
      </div>`;
  }

  function fit(el) { el.style.height = 'auto'; el.style.height = el.scrollHeight + 'px'; }

  let shownId = null;
  let editingLog = null; // 고치고 있는 기록의 번호 (없으면 null)
  DR.renderDetail = function renderDetail(force) {
    const box = $('#detail');
    const t = S.sel ? DR.task(S.sel) : null;
    const a = document.activeElement;
    // 글을 쓰는 중에는 다시 그리지 않아요 (쓰던 글이 사라지지 않게)
    if (!force && t && shownId === t.id && a && box.contains(a) && (a.tagName === 'TEXTAREA' || (a.tagName === 'INPUT' && a.type !== 'checkbox'))) return;
    const memo = $('#dMemo') ? $('#dMemo').value : '';
    if (!t || shownId !== t.id || editingLog >= t.log.length) editingLog = null;
    box.innerHTML = t ? detailHTML(t) : emptyHTML();
    if (t && shownId === t.id && memo) $('#dMemo').value = memo;
    shownId = t ? t.id : null;
    const ti = $('#dTitle');
    if (ti) fit(ti);
    const le = $('#dLogEdit');
    if (le) { fit(le); le.focus(); le.setSelectionRange(le.value.length, le.value.length); }
  };

  // ---------------------------------------------------------------- 남긴 기록 고치기

  function editLog(i) {
    editingLog = i;
    DR.renderDetail(true);
  }

  async function saveLog() {
    const le = $('#dLogEdit');
    const t = DR.task(S.sel);
    if (!le || !t || editingLog === null) return;
    const i = editingLog;
    const v = le.value.trim();
    editingLog = null;
    if (!v) { DR.renderDetail(true); DR.toast('비어 있는 기록은 남길 수 없어요. 지우려면 × 를 눌러 주세요'); return; }
    if (t.log[i] && v === t.log[i].text) { DR.renderDetail(true); return; }
    await DR.act('/api/task/logedit', { id: t.id, i, text: v });
    DR.renderDetail(true);
    DR.toast('기록을 고쳤어요');
  }

  function cancelLog() {
    editingLog = null;
    DR.renderDetail(true);
  }

  // ---------------------------------------------------------------- 고치기

  const save = (patch) => DR.act('/api/task/save', { task: { id: S.sel, ...patch } });

  function minus15(hm) {
    const [h, m] = hm.split(':').map(Number);
    const x = (h * 60 + m - 15 + 1440) % 1440;
    return `${String(Math.floor(x / 60)).padStart(2, '0')}:${String(x % 60).padStart(2, '0')}`;
  }

  function whenMenu(anchor, t, onPick) {
    const nextMon = DR.addDays(DR.weekStart(S.today), 7 + (S.settings.weekStart === 'sun' ? 1 : 0));
    DR.pickDate(anchor, t && t.bucket === 'day' ? t.date : '', (v) => onPick(typeof v === 'string' ? { bucket: 'day', date: v } : v), [
      { label: '오늘', value: S.today },
      { label: '내일', value: DR.addDays(S.today, 1) },
      { label: '다음 주 월요일', value: nextMon },
      { label: '이번 주 안에', value: { bucket: 'week', weekOf: DR.weekStart(S.today) } },
      { label: '언젠가', value: { bucket: 'someday' } },
    ]);
  }
  DR.whenMenu = whenMenu;

  function catMenu(anchor, t) {
    DR.menu([
      ...S.cats.map((c) => ({ label: c.name, icon: `<span class="dot c-${c.color}"></span>`, run: () => DR.act('/api/task/save', { task: { id: t.id, cat: c.id } }) })),
      { label: '분류 없음', icon: '<span class="dot"></span>', run: () => DR.act('/api/task/save', { task: { id: t.id, cat: '' } }) },
      '-',
      { label: '새 분류 만들기…', run: () => DR.openCatForm() },
    ], anchor);
  }
  DR.catMenu = catMenu;

  async function deleteTask(id) {
    const r = await DR.act('/api/task/delete', { id });
    if (!r || !r.deleted) return;
    if (S.sel === id) S.sel = null;
    DR.render();
    DR.lastDeleted = r.deleted;
    DR.toast(`‘${r.deleted.title}’ 할 일을 지웠어요`, { action: { label: '되돌리기', run: () => DR.undoDelete() } });
  }
  DR.deleteTask = deleteTask;
  DR.undoDelete = async function () {
    const t = DR.lastDeleted;
    if (!t) return;
    DR.lastDeleted = null;
    const r = await DR.act('/api/task/save', { task: t });
    if (r && r.task) { S.sel = r.task.id; DR.render(); DR.toast('되돌렸어요'); }
  };

  async function toggle(id) {
    const before = DR.task(id);
    const r = await DR.act('/api/task/toggle', { id });
    if (r && r.task && r.task.done && before && before.repeat) {
      const n = DR.task(r.task.nextId);
      if (n) DR.toast(`끝냈어요 · 다음 차례는 ${n.bucket === 'week' ? DR.md(n.weekOf) + ' 주' : DR.relDay(n.date)}`);
    }
  }
  DR.toggle = toggle;

  async function addLog() {
    const m = $('#dMemo');
    const text = m ? m.value.trim() : '';
    if (!text) { if (m) m.focus(); return; }
    m.value = '';
    await DR.act('/api/task/log', { id: S.sel, text });
    DR.renderDetail(true);
    DR.toast('기록을 남겼어요');
  }

  const box = document.getElementById('detail');
  box.addEventListener('click', (e) => {
    const b = e.target.closest('[data-dact]');
    if (!b) return;
    const t = DR.task(S.sel);
    if (!t) return;
    const a = b.dataset.dact;
    if (a === 'close') { S.sel = null; DR.render(); }
    else if (a === 'star') save({ star: !t.star });
    else if (a === 'delete') deleteTask(t.id);
    else if (a === 'cat') catMenu(b, t);
    else if (a === 'date') whenMenu(b, t, (p) => save(p));
    else if (a === 'due') {
      const fri = (base) => { const ws = DR.weekStart(base); return DR.addDays(ws, S.settings.weekStart === 'sun' ? 5 : 4); };
      DR.pickDate(b, t.due, (v) => save({ due: v }), [
        { label: '오늘', value: S.today }, { label: '내일', value: DR.addDays(S.today, 1) },
        { label: '이번 주 금요일', value: fri(S.today) }, { label: '다음 주 금요일', value: fri(DR.addDays(S.today, 7)) },
      ]);
    }
    else if (a === 'clear') save({ [b.dataset.f]: '' }).then(() => { if (b.dataset.f === 'time') DR.toast('시간을 없앴어요'); });
    else if (a === 'time') DR.pickTime(b, t.time, (v) => save({ time: v }), { title: '시간', clearLabel: t.time ? '시간 없애기' : '', onClear: () => save({ time: '' }).then(() => DR.toast('시간을 없앴어요')) });
    else if (a === 'alarmtime') DR.pickTime(b, t.alarm, (v) => save({ alarm: v }), { title: '알림 시각', clearLabel: '알림 끄기', onClear: () => save({ alarm: '' }) });
    else if (a === 'alarm') save({ alarm: t.alarm ? '' : (t.time ? minus15(t.time) : '09:00') });
    else if (a === 'repeat') save({ repeat: b.dataset.v });
    else if (a === 'calendar') save({ calendar: !t.calendar });
    else if (a === 'progress') DR.act('/api/task/log', { id: t.id, text: '', progress: +b.dataset.v }).then(() => DR.renderDetail(true));
    else if (a === 'addlog') addLog();
    else if (a === 'logedit') editLog(+b.dataset.i);
    else if (a === 'logsave') saveLog();
    else if (a === 'logcancel') cancelLog();
    else if (a === 'logdel') { if (editingLog !== null) editingLog = null; DR.act('/api/task/logdel', { id: t.id, i: +b.dataset.i }).then(() => DR.renderDetail(true)); }
    else if (a === 'toggle') toggle(t.id);
    else if (a === 'tomorrow') save({ bucket: 'day', date: DR.addDays(S.today, 1) }).then(() => DR.toast('내일로 옮겼어요'));
  });

  box.addEventListener('change', (e) => {
    const f = e.target.dataset.field;
    if (!f || !S.sel) return;
    if (f === 'time' || f === 'alarm') save({ [f]: e.target.value || '' });
  });

  box.addEventListener('input', (e) => { if (e.target.id === 'dTitle' || e.target.id === 'dLogEdit') fit(e.target); });
  // 저장 · 취소 단추를 눌러도 글 칸에서 눈길(포커스)이 빠지지 않게 해요 (빠지면 바로 저장돼 버려요)
  box.addEventListener('mousedown', (e) => { if (e.target.closest('.lgbtns button')) e.preventDefault(); });
  box.addEventListener('dblclick', (e) => {
    const x = e.target.closest('.log .x[data-i]');
    if (x) { e.preventDefault(); editLog(+x.dataset.i); }
  });

  box.addEventListener('keydown', (e) => {
    if (e.target.id === 'dTitle' && e.key === 'Enter' && !e.isComposing) { e.preventDefault(); e.target.blur(); }
    if (e.target.id === 'dTitle' && e.key === 'Escape') { const t = DR.task(S.sel); if (t) e.target.value = t.title; e.target.blur(); }
    if (e.target.id === 'dLogEdit') {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); saveLog(); return; }
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); cancelLog(); return; }
    }
    if (e.target.id === 'dMemo' && e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !e.isComposing) { e.preventDefault(); addLog(); }
  });

  box.addEventListener('focusout', (e) => {
    const t = DR.task(S.sel);
    if (!t) return;
    if (e.target.id === 'dTitle') {
      const v = e.target.value.replace(/\s+/g, ' ').trim();
      if (!v) { e.target.value = t.title; return; }
      if (v !== t.title) save({ title: v }).then(() => DR.renderDetail(true));
    }
    if (e.target.id === 'dNote' && e.target.value !== t.note) save({ note: e.target.value });
    // 다른 곳을 누르면 고친 기록을 저장해요
    if (e.target.id === 'dLogEdit' && editingLog !== null) saveLog();
  });
})();

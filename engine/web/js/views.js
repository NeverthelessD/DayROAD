// DayROAD — 화면 그리기 (메뉴 · 오늘 · 이번 주 · 목록들)
'use strict';

(function () {
  const S = DR.S, ICON = DR.ICON;
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = (s, el = document) => el.querySelector(s);

  // ---------------------------------------------------------------- 고르기

  const inWeek = (t, ws) => (t.bucket === 'day' && t.date >= ws && t.date <= DR.addDays(ws, 6)) || (t.bucket === 'week' && t.weekOf === ws);
  const dayTasks = (d) => S.tasks.filter((t) => t.bucket === 'day' && t.date === d);
  const open = (l) => l.filter((t) => !t.done);
  const isDueSoon = (t) => !t.done && t.due && DR.daysBetween(S.today, t.due) <= 3;
  DR.sel = { inWeek, dayTasks };

  function counts() {
    const ws = DR.weekStart(S.today);
    const c = { today: 0, week: 0, due: 0, repeat: 0, someday: 0, cats: {} };
    for (const t of S.tasks) {
      if (t.done) continue;
      if (t.bucket === 'day' && t.date === S.today) c.today++;
      if (inWeek(t, ws)) c.week++;
      if (isDueSoon(t)) c.due++;
      if (t.repeat) c.repeat++;
      if (t.bucket === 'someday') c.someday++;
      if (t.cat) c.cats[t.cat] = (c.cats[t.cat] || 0) + 1;
    }
    return c;
  }

  // ---------------------------------------------------------------- 메뉴 (왼쪽)

  function navBtn(view, icon, label, n, extra = '') {
    const cur = S.view === view && view !== 'cat';
    return `<button type="button" class="nav" data-act="view" data-view="${view}" data-drop-view="${view}" ${cur ? 'aria-current="page"' : ''}>${icon}<span>${label}</span>${extra}${n ? `<span class="n">${n}</span>` : ''}</button>`;
  }

  function renderSide() {
    const c = counts();
    const u = S.update;
    const updOn = u && (u.status === 'ready' || (u.status === 'available' && !u.autoUpdate));
    const cats = S.cats.map((k) => `<button type="button" class="nav catrow c-${k.color}" data-act="cat" data-id="${k.id}" ${S.view === 'cat' && S.catId === k.id ? 'aria-current="page"' : ''}>
        <span class="dot"></span><span>${esc(k.name)}</span><span class="n">${c.cats[k.id] || ''}</span></button>`).join('');
    let calnote = '';
    if (S.native.on) {
      const st = S.native.events;
      if (st === 'full' && S.settings.calendarShow) calnote = `<div class="calnote"><b><span class="dot" style="--c: var(--done)"></span>캘린더 연결됨</b>iCloud · Google 일정을 함께 보여요</div>`;
      else if (st === 'notDetermined') calnote = `<div class="calnote"><b>캘린더 일정도 같이 볼까요?</b>맥에 연결된 iCloud · Google 캘린더를 보여 줘요. <button type="button" data-act="cal-connect">연결하기</button></div>`;
      else if (st === 'denied' || st === 'restricted' || st === 'writeOnly') calnote = `<div class="calnote"><b>캘린더를 볼 수 없어요</b>맥 설정에서 DayROAD의 캘린더 접근을 켜 주세요. <button type="button" data-act="open-privacy" data-pane="calendars">설정 열기</button></div>`;
    }
    $('#side').innerHTML = `
      <div class="logo">${ICON.logo(30)}<b>DayROAD</b></div>
      ${navBtn('today', ICON.sun, '오늘', c.today)}
      ${navBtn('week', ICON.cal, '이번 주', c.week)}
      ${navBtn('due', ICON.clock, '마감 다가옴', c.due)}
      ${navBtn('repeat', ICON.repeat, '반복하는 일', c.repeat)}
      ${navBtn('someday', ICON.list, '언젠가', c.someday)}
      ${navBtn('done', ICON.check, '끝낸 일', 0)}
      <h3>분류</h3>
      ${cats}
      ${S.catForm ? catFormHTML() : '<button type="button" class="nav addcat" data-act="cat-new">+ 분류 추가</button>'}
      <div class="grow"></div>
      ${calnote}
      <button type="button" class="nav" data-act="settings" style="color: var(--muted); font-size: 14px">${ICON.gear}<span>설정</span>${updOn ? '<span class="upddot" title="새 버전"></span>' : ''}</button>
      <div class="madeby">made by. Nevertheless_D</div>`;
    if (S.catForm && S.catForm.focus) {
      const i = $('#catName');
      if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); }
      S.catForm.focus = false;
    }
  }

  function catFormHTML() {
    const f = S.catForm;
    return `<form class="catform" data-form="cat">
      <label for="catName">${f.id ? '분류 이름' : '새 분류 이름'}</label>
      <input id="catName" class="field" value="${esc(f.name)}" placeholder="예: 운동, 육아, 부업" maxlength="20" autocomplete="off">
      <div class="swatches" role="radiogroup" aria-label="색">${DR.PALETTE_KEYS.map((k) => `<button type="button" role="radio" class="sw c-${k}" data-act="cat-color" data-color="${k}" aria-checked="${f.color === k}" aria-label="${DR.PALETTE_NAME[k]}"></button>`).join('')}</div>
      <div style="display: flex; gap: 6px; justify-content: flex-end">
        <button type="button" class="btn sm" data-act="cat-cancel">취소</button>
        <button type="submit" class="btn sm primary">${f.id ? '저장' : '추가'}</button>
      </div>
    </form>`;
  }

  // ---------------------------------------------------------------- 할 일 한 줄

  function metaHTML(t, opts = {}) {
    const parts = [];
    if (opts.showDate) {
      if (t.bucket === 'week') parts.push(`<span class="chip">${t.weekOf === DR.weekStart(S.today) ? '이번 주 안에' : DR.md(t.weekOf) + ' 주'}</span>`);
      else if (t.bucket === 'someday') parts.push('<span class="chip">언젠가</span>');
      else parts.push(`<span class="chip">${esc(DR.relDay(t.date))}</span>`);
    }
    if (t.time) parts.push(`<span class="chip">${t.time}</span>`);
    const d = DR.dueInfo(t);
    if (d && !t.done) parts.push(`<span class="chip${d.warn ? ' warn' : ''}">${d.d} · ${esc(d.short)}</span>`);
    const c = DR.cat(t.cat);
    if (c) parts.push(`<span class="c-${c.color}"><span class="dot" style="width: 8px; height: 8px"></span>${esc(c.name)}</span>`);
    if (t.repeat) parts.push(`<span>${ICON.repeat13}${DR.REPEAT_NAME[t.repeat]}</span>`);
    if (t.alarm && !t.done) parts.push(`<span>${ICON.bell13}${t.alarm}</span>`);
    if (t.calendar && t.bucket === 'day') parts.push(`<span title="캘린더에도 표시">${DR.ICON.cal12}</span>`);
    if (t.carriedFrom && !t.done) parts.push(`<span class="chip carry">${DR.mdShort(t.carriedFrom)}에서 넘어옴</span>`);
    return parts.join('');
  }

  function rowHTML(t, opts = {}) {
    const sel = S.sel === t.id;
    if (t.done) {
      return `<div class="row done${sel ? ' sel' : ''}" data-id="${t.id}" draggable="true">
        <button type="button" class="check on" data-act="toggle" aria-label="다시 남은 일로">${ICON.tick}</button>
        <div class="body"><button type="button" class="ttl" data-act="select">${esc(t.title)}</button>
        ${opts.showDate || t.repeat ? `<div class="meta">${opts.showDate ? `<span class="chip done">${esc(DR.relDay(t.doneAt || t.date))} 끝냄</span>` : ''}${t.repeat ? `<span>${ICON.repeat13}${DR.REPEAT_NAME[t.repeat]} · 다음 차례가 생겼어요</span>` : ''}</div>` : ''}</div>
        <button type="button" class="iconbtn more" data-act="more" aria-label="더 보기">${ICON.dots}</button>
      </div>`;
    }
    const meta = metaHTML(t, opts);
    return `<div class="row${sel ? ' sel' : ''}" data-id="${t.id}" draggable="true">
      <button type="button" class="check" data-act="toggle" aria-label="끝낸 일로 표시">${ICON.tick}</button>
      <div class="body">
        <button type="button" class="ttl" data-act="select">${esc(t.title)}</button>
        ${meta ? `<div class="meta">${meta}</div>` : ''}
      </div>
      ${t.progress > 0 ? `<div class="mini"><span>${t.progress}%</span><div class="bar"><i style="width: ${t.progress}%"></i></div></div>` : ''}
      ${t.star ? `<span class="star" role="img" aria-label="중요">${ICON.star}</span>` : ''}
      <button type="button" class="iconbtn more" data-act="more" aria-label="더 보기">${ICON.dots}</button>
    </div>`;
  }
  DR.rowHTML = rowHTML;

  function section(title, list, opts = {}) {
    if (!list.length) return '';
    return `<section class="sec"><h2>${title} · ${list.length}</h2>${list.map((t) => rowHTML(t, opts)).join('')}</section>`;
  }

  // ---------------------------------------------------------------- 오늘 (날짜 하나)

  function eventsHTML(date) {
    const evs = DR.eventsFor ? DR.eventsFor(date) : [];
    if (!evs.length) return '';
    return `<div class="events"><span class="lbl">${ICON.cal15}캘린더 일정</span>${evs.map((e) => `<span class="ev" title="${esc(e.calendar)}"><span class="dot" style="--c: ${esc(e.color)}"></span>${e.allDay ? '<b>하루 종일</b>' : `<b>${esc(e.time)}</b>`}<span class="tt">${esc(e.title)}</span><span class="src">${esc(e.source)}</span></span>`).join('')}</div>`;
  }

  function progressHTML(total, done) {
    const pct = total ? Math.round((done / total) * 100) : 0;
    return `<div class="prog"><div class="t"><b>${total}개</b> 중 <b class="g">${done}개</b> 끝냈어요</div><div class="bar"><i style="width: ${pct}%"></i></div></div>`;
  }

  function renderToday() {
    const d = S.viewDate;
    const list = dayTasks(d);
    const op = DR.sortTasks(open(list));
    const dn = list.filter((t) => t.done).sort((a, b) => b.updated - a.updated);
    const dt = DR.pd(d);
    const isToday = d === S.today;
    const ws = DR.weekStart(d);
    const strip = Array.from({ length: 7 }, (_, i) => {
      const x = DR.addDays(ws, i);
      const n = dayTasks(x).length;
      const cls = ['day', x === S.today ? 'today' : '', x === d ? 'view' : ''].join(' ');
      return `<button type="button" class="${cls}" data-act="goto-day" data-date="${x}" data-drop-date="${x}" aria-label="${DR.md(x)} ${DR.dow(x)}요일, 할 일 ${n}개"><span class="w">${DR.dow(x)}</span><span class="d">${DR.pd(x).getDate()}</span><span class="c">${n ? n + '개' : '—'}</span></button>`;
    }).join('');
    const rel = isToday ? '' : `<span class="chip${d < S.today ? '' : ' carry'}">${esc(DR.relDay(d))}</span>`;
    $('#mainHead').innerHTML = `
      <div class="head">
        <div>
          <div class="sub">${dt.getFullYear()}년 ${dt.getMonth() + 1}월 ${rel}</div>
          <h1>${dt.getDate()}일 ${DR.dow(d)}요일</h1>
        </div>
        <div class="hright">
          <div class="headbtns">
            <button type="button" class="iconbtn" data-act="day-step" data-n="-1" aria-label="전날">${ICON.left}</button>
            <button type="button" class="btn sm" data-act="goto-day" data-date="${S.today}" ${isToday ? 'disabled' : ''}>오늘</button>
            <button type="button" class="iconbtn" data-act="day-step" data-n="1" aria-label="다음 날">${ICON.right}</button>
          </div>
          ${progressHTML(list.length, dn.length)}
        </div>
      </div>
      <div class="strip">${strip}</div>
      ${eventsHTML(d)}`;
    const carried = op.filter((t) => t.carriedFrom).length;
    let body = DR.updateBanner ? DR.updateBanner() : '';
    if (isToday && carried) body += `<div class="banner">${ICON.arrow}<span class="t">못 끝낸 일 ${carried}개를 오늘로 가져왔어요. 진행 기록은 그대로 남아 있어요.</span></div>`;
    if (!list.length) {
      body += `<div class="empty"><b>${isToday ? '오늘은 아직 할 일이 없어요' : '이 날은 할 일이 없어요'}</b>위 칸에 적고 Enter 를 누르면 바로 생겨요. "내일 3시 치과", "금요일까지 보고서"처럼 적어도 알아들어요.</div>`;
    }
    body += section('남은 일', op);
    body += section('끝낸 일', dn);
    $('#mainBody').innerHTML = body;
  }

  // ---------------------------------------------------------------- 이번 주

  function cardHTML(t) {
    const d = DR.dueInfo(t);
    const c = DR.cat(t.cat);
    const meta = [t.time, t.repeat ? DR.REPEAT_NAME[t.repeat] : '', d && !t.done ? d.d : '', t.progress > 0 && !t.done ? t.progress + '%' : '', c ? c.name : ''].filter(Boolean).join(' · ');
    return `<div class="card${t.done ? ' done' : ''}${S.sel === t.id ? ' sel' : ''}" data-id="${t.id}" draggable="true">
      <button type="button" class="check${t.done ? ' on' : ''}" data-act="toggle" aria-label="${t.done ? '다시 남은 일로' : '끝낸 일로 표시'}">${ICON.tick}</button>
      <span class="b"><button type="button" class="t" data-act="select">${esc(t.title)}</button>
      ${meta ? `<span class="m${c ? ' c-' + c.color : ''}">${c ? '<span class="dot"></span> ' : ''}${esc(meta)}</span>` : ''}</span>
    </div>`;
  }

  function renderWeek() {
    const ws = S.weekOf;
    const wl = DR.weekLabel(ws);
    const all = S.tasks.filter((t) => inWeek(t, ws));
    const done = all.filter((t) => t.done).length;
    const thisWeek = ws === DR.weekStart(S.today);
    $('#mainHead').innerHTML = `
      <div class="head">
        <div><div class="sub">${wl.range}</div><h1>${wl.title}</h1></div>
        <div class="hright">
          <div class="headbtns">
            <button type="button" class="iconbtn" data-act="week-step" data-n="-7" aria-label="지난주">${ICON.left}</button>
            <button type="button" class="btn sm" data-act="week-this" ${thisWeek ? 'disabled' : ''}>이번 주</button>
            <button type="button" class="iconbtn" data-act="week-step" data-n="7" aria-label="다음 주">${ICON.right}</button>
          </div>
          ${progressHTML(all.length, done)}
        </div>
      </div>`;
    const bucket = DR.sortTasks(S.tasks.filter((t) => t.bucket === 'week' && t.weekOf === ws)).sort((a, b) => a.done - b.done);
    const pills = bucket.map((t) => `<span class="pill${t.done ? ' done' : ''}${S.sel === t.id ? ' sel' : ''}" data-id="${t.id}" draggable="true">
        <button type="button" class="check${t.done ? ' on' : ''}" data-act="toggle" aria-label="${t.done ? '다시 남은 일로' : '끝낸 일로 표시'}">${ICON.tick}</button>
        <button type="button" class="t" data-act="select">${esc(t.title)}</button></span>`).join('');
    const addingBucket = DR.colAdd === 'week';
    const cols = Array.from({ length: 7 }, (_, i) => {
      const d = DR.addDays(ws, i);
      const list = dayTasks(d);
      const items = [...DR.sortTasks(open(list)), ...list.filter((t) => t.done)];
      const wd = DR.pd(d).getDay();
      const evs = DR.eventsFor ? DR.eventsFor(d) : [];
      const adding = DR.colAdd === d;
      return `<div class="col${d === S.today ? ' today' : ''}${wd === 0 || wd === 6 ? ' wkend' : ''}" data-drop-date="${d}">
        <div class="ch"><span><span class="w">${DR.dow(d)}</span><span class="d">${DR.pd(d).getDate()}</span></span>${d === S.today ? '<span class="badge">오늘</span>' : ''}</div>
        ${evs.map((e) => `<div class="evcard" title="${esc(e.calendar)} · ${esc(e.source)}">${ICON.cal12}<span><b>${e.allDay ? '종일' : esc(e.time)}</b> ${esc(e.title)}</span></div>`).join('')}
        ${items.map(cardHTML).join('')}
        ${!items.length && !evs.length ? '<div style="padding: 14px 4px; text-align: center; font-size: 12px; color: var(--muted)">비어 있어요</div>' : ''}
        ${adding ? `<input class="colin" data-colin="${d}" placeholder="할 일 적고 Enter" aria-label="${DR.md(d)}에 할 일 추가">` : `<button type="button" class="coladd" data-act="col-add" data-date="${d}">+ 추가</button>`}
      </div>`;
    }).join('');
    $('#mainBody').innerHTML = `
      <div class="wkbucket" data-drop-week="${ws}">
        <span class="lbl"><b>${thisWeek ? '이번 주 안에' : '그 주 안에'}</b><span>요일 상관없이 끝내면 되는 일</span></span>
        ${pills}
        ${addingBucket ? `<input class="colin" style="width: 220px" data-colin="week" placeholder="할 일 적고 Enter" aria-label="이번 주 안에 할 일 추가">` : '<button type="button" class="dashbtn" data-act="col-add" data-date="week">+ 추가</button>'}
      </div>
      <div class="wkscroll"><div class="wkgrid">${cols}</div></div>
      <div class="legend"><span>할 일을 다른 요일이나 '이번 주 안에'로 끌어다 놓으면 날짜가 바뀌어요.</span>${S.native.events === 'full' && S.settings.calendarShow ? '<span><i></i>파란 칸은 iCloud · Google 캘린더 일정</span>' : ''}</div>`;
    const ci = $('[data-colin]');
    if (ci) ci.focus();
  }

  // ---------------------------------------------------------------- 목록 화면들

  function listHead(title, sub) {
    $('#mainHead').innerHTML = `<div class="head"><div><div class="sub">${sub}</div><h1>${title}</h1></div></div>`;
  }

  function grouped(list, keyFn, order) {
    const g = new Map();
    for (const t of list) { const k = keyFn(t); if (!g.has(k)) g.set(k, []); g.get(k).push(t); }
    return order.filter((k) => g.has(k)).map((k) => [k, g.get(k)]);
  }

  function whenGroup(t) {
    if (t.bucket === 'someday') return '언젠가';
    if (t.bucket === 'week') return t.weekOf === DR.weekStart(S.today) ? '이번 주 안에' : '나중 주 안에';
    const n = DR.daysBetween(S.today, t.date);
    if (n < 0) return '지난 날';
    if (n === 0) return '오늘';
    if (n === 1) return '내일';
    if (t.date <= DR.addDays(DR.weekStart(S.today), 6)) return '이번 주';
    if (n <= 31) return '다가오는 날';
    return '나중에';
  }
  const WHEN = ['지난 날', '오늘', '내일', '이번 주', '이번 주 안에', '다가오는 날', '나중 주 안에', '나중에', '언젠가'];
  const byWhen = (a, b) => (a.date || a.weekOf || '9').localeCompare(b.date || b.weekOf || '9') || (a.time || '99').localeCompare(b.time || '99') || a.order - b.order;

  function groupsHTML(groups, opts) {
    return groups.map(([k, l]) => `<section class="sec"><h2>${esc(k)} · ${l.length}</h2>${l.map((t) => rowHTML(t, opts)).join('')}</section>`).join('');
  }

  function renderDue() {
    listHead('마감 다가옴', '마감이 사흘 안에 오거나 지난 일');
    const list = S.tasks.filter(isDueSoon).sort((a, b) => a.due.localeCompare(b.due) || byWhen(a, b));
    const later = S.tasks.filter((t) => !t.done && t.due && !isDueSoon(t)).sort((a, b) => a.due.localeCompare(b.due));
    const key = (t) => { const n = DR.daysBetween(S.today, t.due); return n < 0 ? '마감 지남' : n === 0 ? '오늘까지' : n === 1 ? '내일까지' : '사흘 안'; };
    let body = groupsHTML(grouped(list, key, ['마감 지남', '오늘까지', '내일까지', '사흘 안']), { showDate: true });
    if (later.length) body += `<section class="sec"><h2>그 뒤 · ${later.length}</h2>${later.map((t) => rowHTML(t, { showDate: true })).join('')}</section>`;
    if (!body) body = '<div class="empty"><b>급한 마감이 없어요</b>할 일을 누르고 오른쪽 칸의 "언제까지"를 정하면 여기에 모여요.</div>';
    $('#mainBody').innerHTML = body;
  }

  function renderRepeat() {
    listHead('반복하는 일', '끝내면 다음 차례가 저절로 생겨요');
    const list = S.tasks.filter((t) => !t.done && t.repeat).sort(byWhen);
    const order = ['daily', 'weekdays', 'weekly', 'monthly'];
    const body = order.map((r) => {
      const l = list.filter((t) => t.repeat === r);
      return l.length ? `<section class="sec"><h2>${DR.REPEAT_NAME[r]} · ${l.length}</h2>${l.map((t) => rowHTML(t, { showDate: true })).join('')}</section>` : '';
    }).join('');
    $('#mainBody').innerHTML = body || '<div class="empty"><b>반복하는 일이 없어요</b>"매일 운동 30분", "매주 월 9시 회의"처럼 적거나, 할 일을 누르고 "반복"을 고르세요.</div>';
  }

  function renderSomeday() {
    listHead('언젠가', '날짜를 정하지 않은 일');
    const list = S.tasks.filter((t) => t.bucket === 'someday');
    const op = open(list).sort((a, b) => a.order - b.order);
    const dn = list.filter((t) => t.done).sort((a, b) => b.updated - a.updated);
    $('#mainBody').innerHTML = (section('남은 일', op) + section('끝낸 일', dn)) || '<div class="empty"><b>비어 있어요</b>언젠가 하고 싶은 일을 적어 두세요. 날짜가 정해지면 끌어서 오늘이나 요일로 옮길 수 있어요.</div>';
  }

  function renderDone() {
    listHead('끝낸 일', '최근 넉 달 동안 끝낸 일');
    const list = S.tasks.filter((t) => t.done).sort((a, b) => (b.doneAt || '').localeCompare(a.doneAt || '') || b.updated - a.updated);
    const g = new Map();
    for (const t of list) { const k = t.doneAt || t.date || ''; if (!g.has(k)) g.set(k, []); g.get(k).push(t); }
    const body = [...g.entries()].map(([k, l]) => `<section class="sec"><h2>${k ? esc(DR.relDay(k)) : '날짜 없음'} · ${l.length}</h2>${l.map((t) => rowHTML(t)).join('')}</section>`).join('');
    $('#mainBody').innerHTML = body || '<div class="empty"><b>아직 끝낸 일이 없어요</b>할 일 앞의 네모 칸을 누르면 여기에 쌓여요.</div>';
  }

  function renderCat() {
    const c = DR.cat(S.catId);
    if (!c) { S.view = 'today'; return renderToday(); }
    $('#mainHead').innerHTML = `<div class="head"><div><div class="sub c-${c.color}"><span class="dot"></span>분류</div><h1>${esc(c.name)}</h1></div>
      <div class="headbtns"><button type="button" class="btn sm" data-act="cat-edit" data-id="${c.id}">이름 · 색 바꾸기</button></div></div>`;
    const list = S.tasks.filter((t) => !t.done && t.cat === c.id).sort(byWhen);
    const body = groupsHTML(grouped(list, whenGroup, WHEN), { showDate: true });
    $('#mainBody').innerHTML = body || `<div class="empty"><b>${esc(c.name)} 할 일이 없어요</b>여기서 적으면 이 분류로 들어가요. "#${esc(c.name)}"을 붙여 적어도 돼요.</div>`;
  }

  // ---------------------------------------------------------------- 빠른 추가 칸

  function quickCtx() {
    switch (S.view) {
      case 'today': return { bucket: 'day', date: S.viewDate, hint: S.viewDate === S.today ? '' : DR.relDay(S.viewDate) };
      case 'week': return { bucket: 'week', weekOf: S.weekOf, hint: S.weekOf === DR.weekStart(S.today) ? '이번 주 안에' : DR.weekLabel(S.weekOf).title + ' 안에' };
      case 'someday': return { bucket: 'someday', hint: '언젠가' };
      case 'cat': return { bucket: 'day', date: S.today, cat: S.catId };
      default: return { bucket: 'day', date: S.today };
    }
  }
  DR.quickCtx = quickCtx;

  DR.renderMain = function renderMain() {
    ({ today: renderToday, week: renderWeek, due: renderDue, repeat: renderRepeat, someday: renderSomeday, done: renderDone, cat: renderCat }[S.view] || renderToday)();
    $('#quick').hidden = S.view === 'done';
    if (DR.updateQuickChips) DR.updateQuickChips();
  };
  DR.renderSide = renderSide;

  DR.render = function render() {
    renderSide();
    DR.renderMain();
    DR.renderDetail();
    const appEl = document.getElementById('app');
    appEl.classList.toggle('has-sel', !!S.sel);
    appEl.classList.toggle('drawer', S.view === 'week');
  };
})();

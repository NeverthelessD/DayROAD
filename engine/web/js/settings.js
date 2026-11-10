// DayROAD — 설정 창 · 업데이트 · 분류 관리
'use strict';

(function () {
  const S = DR.S, ICON = DR.ICON;
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = (s, el = document) => el.querySelector(s);
  const TICK = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5L20 7"></path></svg>';
  const BANG = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round" aria-hidden="true"><path d="M12 6v8M12 18v.5"></path></svg>';

  // ---------------------------------------------------------------- 업데이트

  function updateText(u) {
    if (!u) return '';
    switch (u.status) {
      case 'checking': return '새 버전을 확인하는 중…';
      case 'uptodate': return '최신 버전이에요';
      case 'available': return `새 버전 v${u.latest && u.latest.version}이 있어요`;
      case 'downloading': return `새 버전을 받는 중… ${Math.round((u.progress || 0) * 100)}%`;
      case 'installing': return '새 버전을 설치하는 중…';
      case 'ready': return `새 버전 v${u.installed}을 받았어요`;
      case 'error': return u.error || '업데이트를 확인하지 못했어요';
      default: return '새 버전이 나오면 앱이 알아서 받아요';
    }
  }

  DR.updateBanner = function () {
    const u = S.update;
    if (!u) return '';
    if (u.status === 'ready' && u.installed) return `<div class="banner upd"><span class="t">새 버전 <b>v${esc(u.installed)}</b>을 받았어요. 다시 시작하면 바뀌어요.</span><button type="button" class="btn primary sm" data-act="restart">지금 다시 시작</button></div>`;
    if (u.status === 'available' && u.latest && !u.autoUpdate) return `<div class="banner upd"><span class="t">새 버전 <b>v${esc(u.latest.version)}</b>이 나왔어요.</span><button type="button" class="btn primary sm" data-act="install">받기</button></div>`;
    return '';
  };

  DR.installUpdate = async function () {
    try {
      await api('/api/update/install', {});
      S.update = { ...(S.update || {}), status: 'downloading', progress: 0 };
      drawSettings();
      watchUpdate();
    } catch (e) { DR.toastErr(e); }
  };
  function watchUpdate() {
    clearTimeout(watchUpdate.t);
    watchUpdate.t = setTimeout(async () => {
      await DR.poll();
      if (S.update && (S.update.status === 'downloading' || S.update.status === 'installing')) watchUpdate();
    }, 700);
  }
  DR.restartApp = async function () {
    try { await api('/api/update/restart', {}); if (!DR.hasNative()) DR.toast('다시 시작하는 중이에요…'); } catch (e) { DR.toastErr(e); }
  };

  // ---------------------------------------------------------------- 설정 창

  let sm = null;
  DR.openSettings = function openSettings() {
    if (sm) return;
    sm = DR.modal('<div class="sheet" role="dialog" aria-modal="true" aria-label="설정"></div>', { onClose: () => { sm = null; } });
    drawSettings();
    sm.el.addEventListener('click', onClick);
    sm.el.addEventListener('change', onChange);
    if (DR.refreshNative) DR.refreshNative().then(drawSettings);
  };
  DR.drawSettings = drawSettings;

  const sw = (on, act, label) => `<button type="button" class="switch" role="switch" aria-checked="${!!on}" aria-label="${esc(label)}" data-sact="${act}"><span></span></button>`;
  const seg = (cur, act, opts, label) => `<div class="seg" role="radiogroup" aria-label="${esc(label)}">${opts.map(([v, l]) => `<button type="button" role="radio" aria-checked="${cur === v}" data-sact="${act}" data-v="${v}">${l}</button>`).join('')}</div>`;

  function drawSettings() {
    if (!sm) return;
    const s = S.settings, u = S.update || {}, n = S.native;
    const busy = u.status === 'checking' || u.status === 'downloading' || u.status === 'installing';
    const upBtn = u.status === 'ready' ? '<button type="button" class="btn primary" data-sact="restart">다시 시작</button>'
      : u.status === 'available' ? '<button type="button" class="btn primary" data-sact="install">새 버전 받기</button>'
        : `<button type="button" class="btn primary" data-sact="check" ${busy ? 'disabled' : ''}>업데이트 확인</button>`;
    const okUpd = u.status !== 'error' && u.status !== 'available';
    const days = [[0, '당일'], [1, '하루 전'], [2, '이틀 전'], [3, '사흘 전']];

    let cal = '';
    if (!n.on) {
      cal = '<p class="fineprint">캘린더 · 미리 알림 연동과 알림은 맥 앱에서 쓸 수 있어요.</p>';
    } else {
      const evOk = n.events === 'full';
      const evCals = S.calendars.filter((c) => c.kind === 'event');
      const writable = evCals.filter((c) => c.writable);
      const hidden = new Set(s.hiddenCals || []);
      const bySource = {};
      evCals.forEach((c) => { (bySource[c.source] = bySource[c.source] || []).push(c); });
      const calList = evOk && s.calendarShow ? Object.entries(bySource).map(([src, list]) => list.map((c) => `
          <label class="calrow"><input type="checkbox" data-scal="${esc(c.id)}" ${hidden.has(c.id) ? '' : 'checked'}><span class="dot" style="--c: ${esc(c.color)}"></span><span class="nm">${esc(c.title)} <span>· ${esc(src)}</span></span></label>`).join('')).join('') : '';
      const evStatus = evOk ? '<span class="chip done">연결됨</span>'
        : n.events === 'notDetermined' ? '<button type="button" class="btn sm primary" data-act="cal-connect">연결하기</button>'
          : '<button type="button" class="btn sm" data-act="open-privacy" data-pane="calendars">맥 설정 열기</button>';
      const remStatus = n.reminders === 'full' ? '' : n.reminders === 'notDetermined' || !n.reminders ? '' : '<button type="button" class="btn sm" data-act="open-privacy" data-pane="reminders">맥 설정 열기</button>';
      cal = `
        <div class="box">
          <div class="r"><span class="lbl"><b>맥 캘린더</b><span>${evOk ? '맥에 연결된 iCloud · Google 캘린더를 써요' : '맥 캘린더 접근을 허락하면 일정을 함께 보여 줘요'}</span></span><span class="ctl">${evStatus}</span></div>
          ${evOk ? `<div class="r"><span class="lbl"><b>오늘 · 이번 주 화면에 일정 보여 주기</b></span>${sw(s.calendarShow, 'calendarShow', '일정 보여 주기')}</div>` : ''}
          ${calList ? `<div style="border-top: 1px solid var(--line2); padding: 4px 0">${calList}</div>` : ''}
          ${evOk && writable.length ? `<div class="r"><span class="lbl"><b>할 일을 넣을 캘린더</b><span>할 일의 '캘린더에도 표시'를 켜면 여기에 일정이 생겨요</span></span>
            <select class="field" data-sfield="eventCalendar" aria-label="할 일을 넣을 캘린더"><option value="">기본 캘린더</option>${writable.map((c) => `<option value="${esc(c.id)}"${s.eventCalendar === c.id ? ' selected' : ''}>${esc(c.title)} · ${esc(c.source)}</option>`).join('')}</select></div>` : ''}
          <div class="r"><span class="lbl"><b>할 일을 아이폰 '미리 알림'에도 보내기</b><span>미리 알림 앱의 'DayROAD' 목록에 할 일이 함께 생겨요. 아이폰에서 끝내거나 새로 적은 것도 이쪽으로 가져와요</span></span>
            <span class="ctl">${remStatus}${sw(s.remindersSync, 'remindersSync', '미리 알림 보내기')}</span></div>
        </div>
        <p class="fineprint">맥 '시스템 설정 › 인터넷 계정'에 추가된 iCloud · Google 계정을 그대로 써요. 앱에서 따로 로그인하지 않아요.</p>`;
    }

    const notifyWarn = n.on && n.notify === 'denied'
      ? `<div class="status warn"><span class="ok">${BANG}</span><span class="tx"><b>알림이 꺼져 있어요</b><span>할 일 알림 · 아침 알림을 받으려면 맥 설정에서 DayROAD 알림을 켜 주세요</span></span><button type="button" class="btn sm" data-act="open-privacy" data-pane="notifications">맥 설정 열기</button></div>` : '';

    $('.sheet', sm.el).innerHTML = `
      <div class="sh"><h2>설정</h2><button type="button" class="btn ghost sm" data-close style="color: var(--accent-t)">닫기</button></div>
      <div class="sb">
        <section class="about">${ICON.logoBig}<div class="v"><b>DayROAD</b><span>오늘과 이번 주 할 일 · 버전 ${esc(s.build || '')}</span></div></section>
        <div class="status${okUpd ? '' : ' warn'}"><span class="ok">${okUpd ? TICK : BANG}</span><span class="tx"><b>${esc(updateText(u))}</b><span>${u.status === 'ready' ? '다시 시작하면 새 버전으로 바뀌어요' : '새 버전이 나오면 앱이 알아서 받아요'}</span></span>${upBtn}</div>
        <div class="box">
          <div class="r"><span class="lbl"><b>자동으로 업데이트 받기</b></span>${sw(s.autoUpdate, 'autoUpdate', '자동 업데이트')}</div>
          <div class="r"><span class="lbl"><b>한 주의 시작</b></span>${seg(s.weekStart, 'weekStart', [['mon', '월요일'], ['sun', '일요일']], '한 주의 시작')}</div>
          <div class="r"><span class="lbl"><b>화면 모드</b></span>${seg(s.appearance, 'appearance', [['system', '맥 설정 따름'], ['light', '라이트'], ['dark', '다크']], '화면 모드')}</div>
        </div>
        <div class="boxh">할 일 · 알림</div>
        <div class="box">
          <div class="r"><span class="lbl"><b>못 끝낸 일 오늘로 가져오기</b><span>자정이 지나면 어제 남은 일이 오늘 목록으로 와요</span></span>${sw(s.carryOver, 'carryOver', '못 끝낸 일 가져오기')}</div>
          <div class="r"><span class="lbl"><b>아침 알림</b><span>오늘 할 일을 알려 줘요</span></span><span class="ctl">${s.morning.on ? `<input type="time" class="field" value="${esc(s.morning.time)}" data-sfield="morning.time" aria-label="아침 알림 시각">` : ''}${sw(s.morning.on, 'morning.on', '아침 알림')}</span></div>
          <div class="r"><span class="lbl"><b>마감 미리 알려 주기</b><span>'언제까지'가 정해진 일</span></span><span class="ctl">${s.dueRemind.on ? `<select class="field" data-sfield="dueRemind.days" aria-label="며칠 전">${days.map(([v, l]) => `<option value="${v}"${s.dueRemind.days === v ? ' selected' : ''}>${l}</option>`).join('')}</select><input type="time" class="field" value="${esc(s.dueRemind.time)}" data-sfield="dueRemind.time" aria-label="알림 시각">` : ''}${sw(s.dueRemind.on, 'dueRemind.on', '마감 알림')}</span></div>
        </div>
        ${notifyWarn}
        <div class="boxh">캘린더 · 미리 알림 연동</div>
        ${cal}
        <div class="sfoot">
          <span style="display: flex; gap: 16px; flex-wrap: wrap">
            <a href="#" data-sact="diag">진단 정보 보기</a>
            ${u.canRollback ? `<a href="#" data-sact="rollback">이전 버전(v${esc(u.backupVersion)})으로 되돌리기</a>` : ''}
          </span>
          <span style="font-size: 12px; color: var(--muted)">made by. Nevertheless_D</span>
        </div>
      </div>`;
  }

  async function saveSetting(patch) {
    try {
      Object.assign(S.settings, await api('/api/settings', patch));
      DR.applyTheme();
      drawSettings();
      if ('weekStart' in patch) { S.weekOf = DR.weekStart(S.weekOf || S.today); }
      await DR.reload();
      if (DR.settingsChanged) DR.settingsChanged(patch);
    } catch (e) { DR.toastErr(e); }
  }
  DR.saveSetting = saveSetting;

  function setPath(path, value) {
    const [a, b] = path.split('.');
    if (!b) return { [a]: value };
    return { [a]: { ...S.settings[a], [b]: value } };
  }

  async function onClick(e) {
    if (e.target.closest('[data-close]')) return sm.close();
    const b = e.target.closest('[data-sact]');
    if (!b) return;
    const a = b.dataset.sact;
    if (b.getAttribute('role') === 'switch') {
      const [k, k2] = a.split('.');
      const cur = k2 ? S.settings[k][k2] : S.settings[k];
      if (a === 'remindersSync' && !cur && DR.enableReminders) { if (!(await DR.enableReminders())) return; }
      if ((a === 'morning.on' || a === 'dueRemind.on') && !cur && DR.ensureNotify) DR.ensureNotify();
      return saveSetting(setPath(a, !cur));
    }
    if (a === 'weekStart' || a === 'appearance') return saveSetting({ [a]: b.dataset.v });
    if (a === 'check') {
      S.update = { ...(S.update || {}), status: 'checking' }; drawSettings();
      try { S.update = await api('/api/update/check', {}); } catch (err) { DR.toastErr(err); }
      drawSettings(); DR.renderSide();
    }
    if (a === 'install') DR.installUpdate();
    if (a === 'restart') DR.restartApp();
    if (a === 'diag') { e.preventDefault(); if (DR.hasNative()) DR.native('openDiag').catch(() => {}); else window.open('/diag', '_blank'); }
    if (a === 'rollback') {
      e.preventDefault();
      if (!confirm(`이전 버전(v${S.update.backupVersion})으로 되돌릴까요? 되돌린 뒤에는 자동 업데이트가 꺼져요.`)) return;
      try { await api('/api/update/rollback', {}); await DR.poll(); drawSettings(); DR.toast('되돌렸어요. 다시 시작하면 이전 버전으로 열려요', { action: { label: '다시 시작', run: DR.restartApp } }); } catch (err) { DR.toastErr(err); }
    }
  }

  function onChange(e) {
    const f = e.target.dataset.sfield;
    if (f) {
      let v = e.target.value;
      if (f === 'dueRemind.days') v = +v;
      if (f.endsWith('.time') && !v) return;
      return saveSetting(setPath(f, v));
    }
    const c = e.target.dataset.scal;
    if (c) {
      const hidden = new Set(S.settings.hiddenCals || []);
      if (e.target.checked) hidden.delete(c); else hidden.add(c);
      saveSetting({ hiddenCals: [...hidden] });
    }
  }

  // ---------------------------------------------------------------- 분류 관리

  DR.openCatForm = function (cat) {
    const used = new Set(S.cats.map((c) => c.color));
    S.catForm = cat ? { id: cat.id, name: cat.name, color: cat.color, focus: true }
      : { id: '', name: '', color: DR.PALETTE_KEYS.find((k) => !used.has(k)) || 'teal', focus: true };
    DR.renderSide();
  };

  DR.submitCatForm = async function () {
    const f = S.catForm;
    if (!f) return;
    const name = ($('#catName') || {}).value || '';
    if (!name.trim()) { DR.toast('분류 이름을 적어 주세요', { err: true }); return; }
    const r = await DR.act('/api/cat/save', { cat: { id: f.id, name: name.trim(), color: f.color } });
    if (r) { S.catForm = null; DR.render(); DR.toast(f.id ? '분류를 바꿨어요' : `‘${r.cat.name}’ 분류를 만들었어요`); }
  };

  DR.catContext = function (anchor, id) {
    const c = DR.cat(id);
    if (!c) return;
    const i = S.cats.indexOf(c);
    const ids = S.cats.map((x) => x.id);
    const move = (d) => { const j = i + d; if (j < 0 || j >= ids.length) return; [ids[i], ids[j]] = [ids[j], ids[i]]; DR.act('/api/cat/order', { ids }); };
    DR.menu([
      { label: '이름 · 색 바꾸기', run: () => DR.openCatForm(c) },
      ...(i > 0 ? [{ label: '위로 옮기기', run: () => move(-1) }] : []),
      ...(i < ids.length - 1 ? [{ label: '아래로 옮기기', run: () => move(1) }] : []),
      '-',
      { label: '분류 지우기', danger: true, run: async () => {
        const n = S.tasks.filter((t) => t.cat === id).length;
        if (!confirm(`‘${c.name}’ 분류를 지울까요?${n ? `\n이 분류의 할 일 ${n}개는 지워지지 않고 ‘분류 없음’이 돼요.` : ''}`)) return;
        const r = await DR.act('/api/cat/delete', { id });
        if (r) DR.toast('분류를 지웠어요');
      } },
    ], anchor);
  };
})();

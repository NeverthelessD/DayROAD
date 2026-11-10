// DayROAD — 맥과 이어지는 것들: 캘린더 일정 · 캘린더에 할 일 넣기 · 아이폰 '미리 알림' · 알림 예약
// 맥 앱(Swift)이 EventKit · 알림 센터를 맡고, 화면은 무엇을 할지 정해서 부탁해요.
// 앱이 켜져 있을 때 맞춰요. (꺼져 있는 동안 아이폰에서 바꾼 것은 다음에 켤 때 가져와요)
'use strict';

(function () {
  const S = DR.S;
  const N = (type, data) => DR.native(type, data);

  DR.refreshNative = async function () {
    if (!DR.hasNative()) return;
    try {
      const st = await N('status');
      Object.assign(S.native, st);
      if (st.events === 'full' || st.reminders === 'full') {
        const r = await N('calendars');
        S.calendars = (r && r.items) || [];
      }
    } catch (e) { DR.logClient('status: ' + e.message); }
  };

  DR.calConnect = async function () {
    try {
      const r = await N('requestEvents');
      await DR.refreshNative();
      if (r && r.granted) {
        if (!S.settings.calendarShow) await DR.saveSetting({ calendarShow: true });
        DR.toast('캘린더를 연결했어요');
        queueAll();
      } else {
        DR.toast('캘린더 접근을 허락하지 않았어요. 맥 설정에서 켤 수 있어요', { err: true });
      }
      clearEvents();
      DR.render();
      DR.drawSettings();
    } catch (e) { DR.toastErr(e); }
  };

  DR.openPrivacy = (pane) => N('openPrivacy', { pane }).catch(() => {});

  // ---------------------------------------------------------------- 일정 보여 주기

  let evCache = {};
  let wanted = new Set();
  let evTimer = null;
  function clearEvents() { evCache = {}; }
  DR.clearEvents = clearEvents;

  DR.eventsFor = function (date) {
    if (!S.native.on || S.native.events !== 'full' || !S.settings.calendarShow) return [];
    const e = evCache[date];
    if (!e || Date.now() - e.at > 90000) { wanted.add(date); clearTimeout(evTimer); evTimer = setTimeout(fetchEvents, 30); }
    const hidden = new Set(S.settings.hiddenCals || []);
    return e ? e.items.filter((x) => !hidden.has(x.calendarId)) : [];
  };

  let evBusy = false;
  async function fetchEvents() {
    if (evBusy || !wanted.size) return;
    const dates = [...wanted].sort();
    wanted = new Set();
    const from = dates[0], to = dates[dates.length - 1];
    evBusy = true;
    try {
      const r = await N('events', { from, to });
      const by = {};
      for (let d = from; d <= to; d = DR.addDays(d, 1)) by[d] = [];
      for (const x of (r && r.items) || []) if (by[x.date]) by[x.date].push(x);
      let changed = false;
      for (const [d, items] of Object.entries(by)) {
        items.sort((a, b) => (b.allDay - a.allDay) || a.time.localeCompare(b.time));
        const old = evCache[d];
        if (!old || JSON.stringify(old.items) !== JSON.stringify(items)) changed = true;
        evCache[d] = { at: Date.now(), items };
      }
      if (changed) DR.renderMain();
    } catch (e) { DR.logClient('events: ' + e.message); }
    evBusy = false;
    if (wanted.size) fetchEvents();
  }

  // ---------------------------------------------------------------- 할 일 → 캘린더 · 미리 알림

  const calOn = () => S.native.on && S.native.events === 'full';
  const remOn = () => S.native.on && S.native.reminders === 'full' && S.settings.remindersSync;
  const same = (a, b, keys) => keys.every((k) => a[k] === b[k]);

  function calNeeds(t, p) {
    if (!calOn()) return false;
    const want = t.calendar && t.bucket === 'day';
    if (want && !t.eventId) return true;
    if (!want && t.eventId) return true;
    return !!(want && p && !same(t, p, ['title', 'date', 'time', 'bucket', 'note']));
  }
  function remNeeds(t, p) {
    if (!remOn()) return false;
    if (!t.reminderId) return !t.done;
    return !!(p && !same(t, p, ['title', 'date', 'time', 'bucket', 'due', 'done', 'note']));
  }

  const queue = new Map(); // id → {cal, rem}
  let running = false;
  const pendingRem = new Set(); // 방금 만든 미리 알림 (번호를 저장하기 전에 가져오기에서 또 들어오지 않게)

  function enqueue(id, kind) {
    const q = queue.get(id) || {};
    q[kind] = true;
    queue.set(id, q);
    runQueue();
  }

  function queueAll() {
    for (const t of S.tasks) {
      if (calNeeds(t, null)) enqueue(t.id, 'cal');
      if (remNeeds(t, null)) enqueue(t.id, 'rem');
    }
  }
  DR.syncAll = queueAll;

  async function runQueue() {
    if (running) return;
    running = true;
    const links = [];
    try {
      while (queue.size) {
        const [id, q] = queue.entries().next().value;
        queue.delete(id);
        const t = DR.task(id);
        if (!t) continue;
        if (q.cal && calOn()) {
          try {
            if (t.calendar && t.bucket === 'day') {
              const r = await N('eventUpsert', { eventId: t.eventId, calendarId: S.settings.eventCalendar || '', title: t.title, date: t.date, time: t.time, notes: t.note || '' });
              if (r && r.eventId !== t.eventId) links.push({ id, eventId: r.eventId });
            } else if (t.eventId) {
              await N('eventDelete', { eventId: t.eventId });
              links.push({ id, eventId: '' });
            }
          } catch (e) { DR.logClient('event: ' + e.message); }
        }
        if (q.rem && remOn()) {
          try {
            const notes = [t.note || '', t.due ? `마감: ${DR.md(t.due)} (${DR.dow(t.due)})` : ''].filter(Boolean).join('\n');
            const r = await N('reminderUpsert', {
              reminderId: t.reminderId, listId: S.settings.remindersList || '', title: t.title,
              date: t.bucket === 'day' ? t.date : (t.due || ''), time: t.bucket === 'day' ? t.time : '', done: t.done, notes,
            });
            if (r && r.reminderId && r.reminderId !== t.reminderId) { pendingRem.add(r.reminderId); links.push({ id, reminderId: r.reminderId }); }
            if (r && r.listId && r.listId !== S.settings.remindersList) await DR.saveSetting({ remindersList: r.listId });
          } catch (e) { DR.logClient('reminder: ' + e.message); }
        }
      }
      if (links.length) {
        const r = await api('/api/links', { items: links });
        DR.applyState(r);
        DR.render();
      }
    } finally {
      pendingRem.clear();
      running = false;
      if (queue.size) runQueue();
    }
  }

  // 엔진에서 새 상태를 받을 때마다: 바뀐 할 일만 맞춰요
  DR.afterState = function (prev) {
    if (!DR.hasNative()) return;
    const cur = new Set();
    for (const t of S.tasks) {
      cur.add(t.id);
      const p = prev.get(t.id);
      if (calNeeds(t, p)) enqueue(t.id, 'cal');
      if (remNeeds(t, p)) enqueue(t.id, 'rem');
    }
    for (const [id, p] of prev) {
      if (cur.has(id)) continue;
      if (p.eventId && calOn()) N('eventDelete', { eventId: p.eventId }).catch(() => {});
      if (p.reminderId && remOn()) N('reminderDelete', { reminderId: p.reminderId }).catch(() => {});
    }
    scheduleNotify();
  };

  // ---------------------------------------------------------------- 아이폰 '미리 알림'에서 가져오기

  let pulling = false;
  DR.pullReminders = async function () {
    if (!remOn() || pulling || running) return;
    pulling = true;
    try {
      const r = await N('reminderFetch', { listId: S.settings.remindersList || '' });
      const items = (r && r.items) || [];
      const byRid = new Map(S.tasks.filter((t) => t.reminderId).map((t) => [t.reminderId, t]));
      const doneIds = items.filter((x) => x.done && byRid.has(x.id) && !byRid.get(x.id).done).map((x) => byRid.get(x.id).id);
      const fresh = items.filter((x) => !x.done && !byRid.has(x.id) && !pendingRem.has(x.id));
      if (doneIds.length) {
        const s = await api('/api/sync/done', { ids: doneIds });
        DR.applyState(s);
        DR.toast(`아이폰에서 끝낸 일 ${doneIds.length}개를 반영했어요`);
      }
      if (fresh.length) {
        const s = await api('/api/import', { items: fresh.map((x) => ({ title: x.title, due: x.date || '', time: x.time || '', note: x.notes || '', reminderId: x.id })) });
        DR.applyState(s);
        if (s.count) DR.toast(`아이폰에서 적은 할 일 ${s.count}개를 가져왔어요`);
      }
      if (doneIds.length || fresh.length) DR.render();
    } catch (e) { DR.logClient('pull: ' + e.message); }
    pulling = false;
  };

  DR.enableReminders = async function () {
    try {
      const r = await N('requestReminders');
      await DR.refreshNative();
      if (!r || !r.granted) {
        DR.toast('미리 알림 접근을 허락하지 않았어요. 맥 설정에서 켤 수 있어요', { err: true });
        DR.drawSettings();
        return false;
      }
      const l = await N('reminderList', { listId: S.settings.remindersList || '' });
      if (l && l.listId) await DR.saveSetting({ remindersList: l.listId });
      return true;
    } catch (e) { DR.toastErr(e); return false; }
  };

  DR.settingsChanged = function (patch) {
    if ('remindersSync' in patch && S.settings.remindersSync) { queueAll(); setTimeout(DR.pullReminders, 1500); DR.toast("할 일을 '미리 알림'의 DayROAD 목록에 보내는 중이에요"); }
    if ('calendarShow' in patch || 'hiddenCals' in patch) { clearEvents(); DR.renderMain(); }
    if ('eventCalendar' in patch) { /* 새로 만드는 일정부터 적용 */ }
    if ('morning' in patch || 'dueRemind' in patch) scheduleNotify(true);
  };

  // ---------------------------------------------------------------- 알림 예약

  let lastSent = '';
  let ntimer = null;
  function scheduleNotify(force) {
    if (!DR.hasNative()) return;
    clearTimeout(ntimer);
    ntimer = setTimeout(() => sendNotify(force), 1200);
  }
  DR.scheduleNotify = scheduleNotify;

  function buildNotify() {
    const items = [];
    const now = new Date();
    const at = (date, hm) => `${date}T${hm}`;
    const s = S.settings;
    for (let i = 0; i < 8; i++) {
      const d = DR.addDays(S.today, i);
      const list = S.tasks.filter((t) => !t.done && t.bucket === 'day' && t.date === d);
      for (const t of list) {
        if (!t.alarm) continue;
        const bits = [t.time ? DR.fmtTime(t.time) : '', t.progress > 0 ? `${t.progress}%까지 했어요` : '', t.due ? (DR.dueInfo(t) || {}).short : ''].filter(Boolean);
        items.push({ id: 'a-' + t.id, title: t.title, body: bits.join(' · ') || '할 일 알림', at: at(d, t.alarm) });
      }
      if (s.morning && s.morning.on) {
        const sorted = DR.sortTasks(list);
        if (sorted.length) items.push({ id: 'm-' + d, title: `오늘 할 일 ${sorted.length}개`, body: sorted.slice(0, 3).map((t) => (t.time ? t.time + ' ' : '') + t.title).join(' · ') + (sorted.length > 3 ? ` 외 ${sorted.length - 3}개` : ''), at: at(d, s.morning.time) });
      }
    }
    if (s.dueRemind && s.dueRemind.on) {
      for (const t of S.tasks) {
        if (t.done || !t.due) continue;
        const nd = DR.addDays(t.due, -(s.dueRemind.days || 0));
        if (nd < S.today || nd > DR.addDays(S.today, 7)) continue;
        const n = DR.daysBetween(nd, t.due);
        items.push({ id: 'd-' + t.id, title: t.title, body: n === 0 ? '오늘까지예요' : n === 1 ? '내일까지예요' : `${DR.md(t.due)} (${DR.dow(t.due)})까지예요`, at: at(nd, s.dueRemind.time) });
      }
    }
    const nowKey = `${DR.fd(now)}T${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    return items.filter((x) => x.at > nowKey).sort((a, b) => a.at.localeCompare(b.at)).slice(0, 60);
  }
  DR.buildNotify = buildNotify;

  async function sendNotify(force) {
    const items = buildNotify();
    const key = JSON.stringify(items);
    if (!force && key === lastSent) return;
    if (!items.length && !lastSent) { lastSent = key; return; }
    try {
      const r = await N('notifySchedule', { items });
      lastSent = key;
      if (r && r.status && r.status !== S.native.notify) { S.native.notify = r.status; DR.drawSettings(); }
    } catch (e) { DR.logClient('notify: ' + e.message); }
  }
  DR.ensureNotify = async () => { try { const r = await N('requestNotify'); S.native.notify = (r && r.status) || S.native.notify; } catch (e) { /* 없음 */ } };

  // ---------------------------------------------------------------- 맥 앱이 알려 주는 것

  DR.nativeHandlers.focus = () => {
    DR.reload();
    clearEvents();
    DR.refreshNative().then(() => { DR.renderSide(); DR.renderMain(); });
    DR.pullReminders();
  };
  setInterval(() => { if (document.visibilityState === 'visible') DR.pullReminders(); }, 120000);
})();

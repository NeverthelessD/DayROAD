// DayROAD — 빠른 추가 글 읽기
// "금요일까지 보고서" · "내일 오후 3시 치과" · "매주 월 9시 회의" · "#공부 영어 단어 !" 처럼 적으면
// 날짜 · 시간 · 마감 · 반복 · 분류 · 중요를 알아서 나눠요. 알아들은 것은 입력 칸 아래에 작은 표시로 보여 줘요.
'use strict';

(function () {
  const WD = { 일: 0, 월: 1, 화: 2, 수: 3, 목: 4, 금: 5, 토: 6 };
  const sp = '(?:^|\\s)';
  const end = '(?=\\s|$|[,.])';

  // 기준 날짜(base)부터 그 요일이 처음 오는 날 (오늘이 그 요일이면 오늘)
  function nextWd(base, wd) {
    const d = DR.pd(base);
    d.setDate(d.getDate() + ((wd - d.getDay() + 7) % 7));
    return DR.fd(d);
  }
  function inWeek(weekFirst, wd) {
    const ws = DR.S.settings.weekStart === 'sun' ? 0 : 1;
    return DR.addDays(weekFirst, (wd - ws + 7) % 7);
  }

  function hourOf(ap, h, m) {
    h = +h; m = +(m || 0);
    if (h > 24 || m > 59) return null;
    if (ap === '오후' || ap === '저녁' || ap === '밤' || ap === '낮') { if (h < 12) h += 12; if (ap === '낮' && h > 17) h -= 12; }
    else if (ap === '오전' || ap === '아침' || ap === '새벽') { if (h === 12) h = 0; }
    else if (h >= 1 && h <= 6) h += 12; // "3시" 는 보통 오후 3시
    if (h === 24) h = 0;
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
  }

  // 날짜 낱말 → {date} 또는 {week: true} 또는 {someday: true}
  function dateOf(word, base) {
    const today = DR.S.today;
    const w = word.replace(/\s+/g, '');
    let m;
    if (w === '오늘') return { date: today };
    if (w === '내일') return { date: DR.addDays(today, 1) };
    if (w === '모레') return { date: DR.addDays(today, 2) };
    if (w === '글피') return { date: DR.addDays(today, 3) };
    if (w === '언젠가') return { someday: true };
    if (w === '이번주') return { week: DR.weekStart(today) };
    if (w === '다음주' || w === '담주') return { week: DR.addDays(DR.weekStart(today), 7) };
    if ((m = w.match(/^(이번주|다음주|담주)?([월화수목금토일])요일$/))) {
      const wd = WD[m[2]];
      if (m[1] === '이번주') return { date: inWeek(DR.weekStart(today), wd) };
      if (m[1]) return { date: inWeek(DR.addDays(DR.weekStart(today), 7), wd) };
      return { date: nextWd(today, wd) };
    }
    if ((m = w.match(/^(\d{1,2})월(\d{1,2})일$/)) || (m = w.match(/^(\d{1,2})\/(\d{1,2})$/))) {
      const y = DR.pd(today).getFullYear();
      let d = new Date(y, +m[1] - 1, +m[2]);
      if (d.getMonth() !== +m[1] - 1) return null;
      if (DR.fd(d) < today) d = new Date(y + 1, +m[1] - 1, +m[2]);
      return { date: DR.fd(d) };
    }
    void base;
    return null;
  }

  const DATE_WORD = '(오늘|내일|모레|글피|언젠가|(?:이번\\s?주|다음\\s?주|담주)\\s?[월화수목금토일]요일|[월화수목금토일]요일|\\d{1,2}월\\s?\\d{1,2}일|\\d{1,2}\\/\\d{1,2}|이번\\s?주|다음\\s?주|담주)';

  DR.parseQuick = function parseQuick(text, ctx = {}) {
    const base = ctx.date || DR.S.today;
    const out = { chips: [] };
    let s = ' ' + text.trim() + ' ';
    const take = (re, fn) => {
      s = s.replace(re, (...a) => { const r = fn(...a); return r === false ? a[0] : ' '; });
    };

    const findCat = (name) => DR.S.cats.find((x) => x.name === name) || DR.S.cats.find((x) => x.name.toLowerCase() === name.toLowerCase())
      || DR.S.cats.find((x) => x.name.startsWith(name));

    // 분류: "분류는 사역," · "분류: 사역" · "분류 사역," — 없는 분류면 새로 만들어요
    // ("분류 작업 하기"처럼 그냥 낱말로 쓴 것은 건드리지 않게: '는 · 은 · :' 가 붙거나 이름 뒤에 쉼표가 있을 때만)
    take(/(?:^|\s)분류\s*(?:(?:는|은|:|：|=)\s*([^\s,，.。#]+)\s*[,，]?|\s+([^\s,，.。#]+)\s*[,，])(?=\s|$)/, (all, n1, n2) => {
      let name = (n1 || n2 || '').replace(/(으로|로|에)$/, '');
      if (!name) return false;
      const c = findCat(name);
      if (c) { out.cat = c.id; out.chips.push('#' + c.name); } else { out.newCat = name.slice(0, 20); out.chips.push(`새 분류 ‘${out.newCat}’`); }
    });

    // 분류: #이름
    if (!out.cat && !out.newCat) {
      take(new RegExp(sp + '#(\\S+)' + end, 'g'), (all, name) => {
        const c = findCat(name);
        if (!c) return false;
        out.cat = c.id; out.chips.push('#' + c.name);
      });
    }

    // 중요
    take(new RegExp(sp + '(중요|!)' + end, 'g'), () => { out.star = true; });
    if (/\S!$/.test(s.trim())) { s = s.trim().slice(0, -1) + ' '; out.star = true; }
    if (out.star) out.chips.push('중요');

    // 반복
    take(new RegExp(sp + '매주\\s?([월화수목금토일])(?:요일)?(?:마다)?' + end), (all, d) => { out.repeat = 'weekly'; out.date = nextWd(base > DR.S.today ? base : DR.S.today, WD[d]); out.chips.push(`매주 ${d}요일`); });
    take(new RegExp(sp + '([월화수목금토일])요일마다' + end), (all, d) => { out.repeat = 'weekly'; out.date = nextWd(DR.S.today, WD[d]); out.chips.push(`매주 ${d}요일`); });
    take(new RegExp(sp + '매(?:달|월)\\s?(\\d{1,2})일' + end), (all, n) => {
      if (+n < 1 || +n > 31) return false;
      out.repeat = 'monthly';
      const t = DR.pd(DR.S.today);
      let d = new Date(t.getFullYear(), t.getMonth(), +n);
      if (DR.fd(d) < DR.S.today) d = new Date(t.getFullYear(), t.getMonth() + 1, +n);
      out.date = DR.fd(d); out.chips.push(`매달 ${n}일`);
    });
    take(new RegExp(sp + '(매일|날마다)' + end), () => { out.repeat = 'daily'; out.chips.push('매일'); });
    take(new RegExp(sp + '평일(?:마다)?' + end), () => { out.repeat = 'weekdays'; out.chips.push('평일마다'); });
    take(new RegExp(sp + '매주(?:마다)?' + end), () => { out.repeat = 'weekly'; out.chips.push('매주'); });
    take(new RegExp(sp + '매(?:달|월)(?:마다)?' + end), () => { out.repeat = 'monthly'; out.chips.push('매달'); });

    // 날짜 · 마감 ("…까지" 는 마감)
    take(new RegExp(sp + DATE_WORD + '(까지|에는|에)?' + end, 'g'), (all, word, post) => {
      const d = dateOf(word, base);
      if (!d) return false;
      if (post === '까지') {
        if (d.someday) return false;
        out.due = d.date || DR.addDays(d.week, 6);
        out.chips.push(`${DR.relDay(out.due)}까지`);
        return;
      }
      if (d.someday) { out.bucket = 'someday'; out.chips.push('언젠가'); return; }
      if (d.week) { out.bucket = 'week'; out.weekOf = d.week; out.chips.push(d.week === DR.weekStart(DR.S.today) ? '이번 주 안에' : '다음 주 안에'); return; }
      if (out.date && out.repeat) return false;
      out.date = d.date; out.bucket = 'day'; out.chips.push(DR.relDay(d.date));
    });

    // 시간
    take(new RegExp(sp + '(오전|오후|아침|저녁|밤|낮|새벽)?\\s?(\\d{1,2})시(?:\\s?(\\d{1,2})분|\\s?(반))?(에|까지)?' + end), (all, ap, h, m, half, post) => {
      const t = hourOf(ap, h, half ? 30 : m);
      if (!t) return false;
      out.time = t; out.chips.push(DR.fmtTime(t) + (post === '까지' ? '까지' : ''));
    });
    if (!out.time) {
      take(new RegExp(sp + '(오전|오후)?\\s?(\\d{1,2}):(\\d{2})' + end), (all, ap, h, m) => {
        const t = ap ? hourOf(ap, h, m) : (+h < 24 && +m < 60 ? `${String(+h).padStart(2, '0')}:${m}` : null);
        if (!t) return false;
        out.time = t; out.chips.push(DR.fmtTime(t));
      });
    }

    if (out.repeat && !out.date && out.bucket !== 'week') out.date = base;
    if (out.repeat === 'weekly' && out.bucket === 'week') { /* 매주 '이번 주 안에' */ }
    // 남은 글 다듬기: 빈 쉼표 · 앞뒤 쉼표 지우기
    out.title = s.replace(/\s+/g, ' ').replace(/(\s*[,，]\s*)+/g, ', ').replace(/^[\s,，·]+|[\s,，·]+$/g, '').trim();
    if (!out.title) return { title: text.trim(), chips: [] };
    return out;
  };
})();

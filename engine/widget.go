package main

// 위젯과 주고받는 파일 (Support/widget/)
//   widget.json   : 엔진이 씀 — 오늘 할 일 · 이번 주 숫자 (위젯이 읽어서 그려요)
//   actions.jsonl : 위젯이 씀 — 위젯에서 체크박스를 누른 기록 {"id":"…","done":true}
//                   앱이 꺼져 있을 때 누른 것도 다음에 앱을 켜면 그대로 반영돼요.
// 위젯은 맥의 보호 상자(샌드박스) 안에서 돌아서, 이 폴더 하나만 읽고 쓸 수 있게 허락받았어요.

import (
	"bufio"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

var dowNames = []string{"일", "월", "화", "수", "목", "금", "토"}

type widgetItem struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Time      string `json:"time"`
	Done      bool   `json:"done"`
	Color     string `json:"color"`
	ColorDark string `json:"colorDark"`
	Badge     string `json:"badge"`
}

type widgetDay struct {
	Dow   string `json:"dow"`
	Day   int    `json:"day"`
	Total int    `json:"total"`
	Done  int    `json:"done"`
	Today bool   `json:"today"`
}

type widgetData struct {
	V         int          `json:"v"`
	Date      string       `json:"date"`
	Dow       string       `json:"dow"`
	Day       int          `json:"day"`
	Month     int          `json:"month"`
	Total     int          `json:"total"`
	Done      int          `json:"done"`
	Items     []widgetItem `json:"items"`
	Next      *widgetItem  `json:"next"`
	Week      []widgetDay  `json:"week"`
	WeekLabel string       `json:"weekLabel"`
	WeekTotal int          `json:"weekTotal"`
	WeekDone  int          `json:"weekDone"`
	Updated   int64        `json:"updated"`
	// 앱이 꺼진 채로 날짜가 바뀌어도 위젯이 맞게 보이도록: 앞으로 8일 동안의 할 일과 '넘기기' 설정
	Days  map[string][]widgetItem `json:"days"`
	Carry bool                    `json:"carry"`
}

func (s *Store) widgetDir() string { return filepath.Join(s.dir, "widget") }

// sortDay: 시간이 정해진 일은 시간 순서로 먼저, 나머지는 만든 순서
func sortDay(ts []*Task) {
	sort.SliceStable(ts, func(i, j int) bool {
		a, b := ts[i], ts[j]
		if a.Done != b.Done {
			return !a.Done
		}
		ta, tb := a.Time, b.Time
		if ta == "" {
			ta = "99"
		}
		if tb == "" {
			tb = "99"
		}
		if ta != tb {
			return ta < tb
		}
		return a.Order < b.Order
	})
}

func dueBadge(due, today string) string {
	if due == "" {
		return ""
	}
	n := daysBetween(today, due)
	switch {
	case n < 0:
		return "마감 지남"
	case n == 0:
		return "D-day"
	default:
		return "D-" + itoa(n)
	}
}

func itoa(n int) string { return strconv.Itoa(n) }

func (s *Store) widgetLocked() widgetData {
	today := Today()
	t0 := pd(today)
	w := widgetData{V: 1, Date: today, Dow: dowNames[t0.Weekday()] + "요일", Day: t0.Day(), Month: int(t0.Month()), Updated: time.Now().UnixMilli()}
	colors := func(cat string) (string, string) {
		if c := s.cat(cat); c != nil {
			if p, ok := palette[c.Color]; ok {
				return p[0], p[1]
			}
		}
		return "", ""
	}
	var day []*Task
	for _, t := range s.d.Tasks {
		if t.Bucket == "day" && t.Date == today {
			day = append(day, t)
		}
	}
	sortDay(day)
	now := time.Now().Format("15:04")
	for _, t := range day {
		w.Total++
		if t.Done {
			w.Done++
		}
		l, d := colors(t.Cat)
		it := widgetItem{ID: t.ID, Title: t.Title, Time: t.Time, Done: t.Done, Color: l, ColorDark: d, Badge: dueBadge(t.Due, today)}
		if len(w.Items) < 12 {
			w.Items = append(w.Items, it)
		}
		if !t.Done && w.Next == nil && (t.Time == "" || t.Time >= now || env("TODAY") != "") {
			c := it
			w.Next = &c
		}
	}
	if w.Next == nil {
		for _, t := range day {
			if !t.Done {
				l, d := colors(t.Cat)
				w.Next = &widgetItem{ID: t.ID, Title: t.Title, Time: t.Time, Color: l, ColorDark: d}
				break
			}
		}
	}
	ws := weekStartOf(today, app0WeekStart())
	end := addDays(ws, 6)
	for i := 0; i < 7; i++ {
		d := addDays(ws, i)
		dt := pd(d)
		wd := widgetDay{Dow: dowNames[dt.Weekday()], Day: dt.Day(), Today: d == today}
		for _, t := range s.d.Tasks {
			if t.Bucket == "day" && t.Date == d {
				wd.Total++
				if t.Done {
					wd.Done++
				}
			}
		}
		w.WeekTotal += wd.Total
		w.WeekDone += wd.Done
		w.Week = append(w.Week, wd)
	}
	for _, t := range s.d.Tasks {
		if t.Bucket == "week" && t.WeekOf >= ws && t.WeekOf <= end {
			w.WeekTotal++
			if t.Done {
				w.WeekDone++
			}
		}
	}
	a, b := pd(ws), pd(end)
	if a.Month() == b.Month() {
		w.WeekLabel = itoa(int(a.Month())) + "월 " + itoa(a.Day()) + "일 – " + itoa(b.Day()) + "일"
	} else {
		w.WeekLabel = itoa(int(a.Month())) + "월 " + itoa(a.Day()) + "일 – " + itoa(int(b.Month())) + "월 " + itoa(b.Day()) + "일"
	}
	if w.Items == nil {
		w.Items = []widgetItem{}
	}
	w.Carry = carryOn()
	w.Days = map[string][]widgetItem{}
	for i := 1; i <= 8; i++ {
		d := addDays(today, i)
		var l []*Task
		for _, t := range s.d.Tasks {
			if t.Bucket == "day" && t.Date == d && !t.Done {
				l = append(l, t)
			}
		}
		sortDay(l)
		items := []widgetItem{}
		for _, t := range l {
			if len(items) >= 12 {
				break
			}
			c1, c2 := colors(t.Cat)
			items = append(items, widgetItem{ID: t.ID, Title: t.Title, Time: t.Time, Color: c1, ColorDark: c2, Badge: dueBadge(t.Due, d)})
		}
		w.Days[d] = items
	}
	return w
}

// exportWidget: s.mu 를 잡은 채로 불러요
func (s *Store) exportWidget() {
	dir := s.widgetDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	b, err := json.Marshal(s.widgetLocked())
	if err != nil {
		return
	}
	writeFileAtomic(filepath.Join(dir, "widget.json"), b, 0o644)
	s.lastExp = Today()
}

// applyWidgetActions: 위젯에서 누른 체크박스를 반영해요
func (s *Store) applyWidgetActions() {
	p := filepath.Join(s.widgetDir(), "actions.jsonl")
	if !fileExists(p) {
		return
	}
	work := p + ".work"
	if err := os.Rename(p, work); err != nil {
		return
	}
	f, err := os.Open(work)
	if err != nil {
		return
	}
	type act struct {
		ID   string `json:"id"`
		Done bool   `json:"done"`
	}
	var acts []act
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var a act
		if json.Unmarshal([]byte(strings.TrimSpace(sc.Text())), &a) == nil && a.ID != "" {
			acts = append(acts, a)
		}
	}
	f.Close()
	os.Remove(work)
	if len(acts) == 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, a := range acts {
		if t := s.task(a.ID); t != nil && t.Done != a.Done {
			s.setDone(t, a.Done)
			n++
		}
	}
	log.Printf("위젯에서 누른 것 %d개 반영 (기록 %d줄)", n, len(acts))
	s.commit()
}

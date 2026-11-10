package main

// 할 일 저장소
//
// 모든 할 일과 분류는 Support/data.json 한 파일에 있어요 (바뀔 때마다 바로 저장, 하루에 한 번 backups/ 에 복사).
// 날짜 규칙
//   - 할 일은 세 가지 칸 중 하나에 있어요: day(정한 날짜) · week(이번 주 안에) · someday(언젠가)
//   - 날짜가 바뀌면(자정 지나서 · 앱을 켤 때) 못 끝낸 일을 오늘로 가져와요 (설정 '못 끝낸 일 오늘로 가져오기').
//     처음 날짜는 carriedFrom 에 남아서 화면에 "11/9에서 넘어옴" 으로 보여요. 진행 기록은 그대로예요.
//   - 반복하는 일은 넘기지 않고, 놓친 날은 건너뛰어 다음 차례(오늘 이후)로 옮겨요.
//     끝내면 바로 다음 차례가 새로 생기고(nextId), 끝냄을 되돌리면 손대지 않은 다음 차례는 지워요.

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type LogEntry struct {
	Date     string `json:"date"`
	Text     string `json:"text"`
	Progress int    `json:"progress"`
}

type Task struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Note        string     `json:"note"`
	Bucket      string     `json:"bucket"` // day | week | someday
	Date        string     `json:"date"`   // day: YYYY-MM-DD
	WeekOf      string     `json:"weekOf"` // week: 그 주의 첫날
	Time        string     `json:"time"`   // HH:MM 또는 ""
	Cat         string     `json:"cat"`
	Star        bool       `json:"star"`
	Done        bool       `json:"done"`
	DoneAt      string     `json:"doneAt"`
	Due         string     `json:"due"`    // 언제까지 (YYYY-MM-DD)
	Alarm       string     `json:"alarm"`  // 알림 시각 HH:MM (날짜는 Date)
	Repeat      string     `json:"repeat"` // "" | daily | weekdays | weekly | monthly
	Progress    int        `json:"progress"`
	Log         []LogEntry `json:"log"`
	CarriedFrom string     `json:"carriedFrom"`
	Calendar    bool       `json:"calendar"` // 캘린더에도 표시
	EventID     string     `json:"eventId"`
	ReminderID  string     `json:"reminderId"`
	NextID      string     `json:"nextId"`
	Order       float64    `json:"order"`
	Created     int64      `json:"created"`
	Updated     int64      `json:"updated"`
}

type Category struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
	Order int    `json:"order"`
}

type storeData struct {
	V       int         `json:"v"`
	Tasks   []*Task     `json:"tasks"`
	Cats    []*Category `json:"cats"`
	LastDay string      `json:"lastDay"`
}

type Store struct {
	mu      sync.Mutex
	dir     string
	d       storeData
	rev     int64
	lastExp string
}

// 분류 색 (화면 css 와 위젯이 같은 값을 써요)
var palette = map[string][2]string{
	"blue":   {"#3366B0", "#7EA6E6"},
	"orange": {"#C9502A", "#F2936B"},
	"purple": {"#6650B8", "#A796EA"},
	"green":  {"#2F7D50", "#6FC08F"},
	"teal":   {"#1F7A80", "#6CC3C8"},
	"gold":   {"#9A6B0F", "#E0B25C"},
	"pink":   {"#B23A5B", "#E58AA3"},
	"slate":  {"#56606E", "#A9B2BE"},
}

func NewStore(dir string) *Store {
	s := &Store{dir: dir}
	s.load()
	return s
}

func (s *Store) path() string { return filepath.Join(s.dir, "data.json") }

func (s *Store) load() {
	b, err := os.ReadFile(s.path())
	if err == nil {
		if err := json.Unmarshal(b, &s.d); err != nil {
			// 망가진 파일은 지우지 않고 옆에 남겨 두고, 가장 최근 백업으로 시작해요
			bad := s.path() + ".broken-" + time.Now().Format("20060102-150405")
			os.Rename(s.path(), bad)
			log.Printf("⚠️ data.json 을 읽지 못해서 %s 로 옮겼어요: %v", bad, err)
			s.d = storeData{}
			if bk := s.latestBackup(); bk != "" {
				if b, err := os.ReadFile(bk); err == nil && json.Unmarshal(b, &s.d) == nil {
					log.Printf("백업 %s 로 되살렸어요", bk)
				}
			}
		}
	}
	if s.d.V == 0 && len(s.d.Tasks) == 0 && len(s.d.Cats) == 0 {
		s.seed()
	}
	s.d.V = 1
	for _, t := range s.d.Tasks {
		s.normalize(t)
	}
	s.rev = time.Now().UnixMilli()
}

func (s *Store) latestBackup() string {
	m, _ := filepath.Glob(filepath.Join(s.dir, "backups", "data-*.json"))
	sort.Strings(m)
	if len(m) == 0 {
		return ""
	}
	return m[len(m)-1]
}

// seed: 처음 켰을 때 쓰는 법을 알려 주는 할 일 몇 개
func (s *Store) seed() {
	s.d.Cats = []*Category{
		{ID: "work", Name: "일", Color: "blue", Order: 0},
		{ID: "personal", Name: "개인", Color: "orange", Order: 1},
		{ID: "study", Name: "공부", Color: "purple", Order: 2},
		{ID: "health", Name: "건강", Color: "green", Order: 3},
	}
	today := Today()
	now := time.Now().UnixMilli()
	mk := func(i int, title, cat string, log []LogEntry) *Task {
		return &Task{ID: randID(6), Title: title, Bucket: "day", Date: today, Cat: cat, Log: log,
			Order: float64(now + int64(i)), Created: now, Updated: now}
	}
	s.d.Tasks = []*Task{
		mk(0, "할 일 이름을 눌러 자세히 보기", "personal", []LogEntry{{Date: today, Text: "오른쪽 칸에서 마감일 · 알림 · 반복을 정하고, 어디까지 했는지 적어 둘 수 있어요."}}),
		mk(1, "네모 칸을 눌러 끝내기", "personal", nil),
		mk(2, "바탕화면에 위젯 올리기", "personal", []LogEntry{{Date: today, Text: "바탕화면을 오른쪽 클릭 › '위젯 편집' › DayROAD 를 골라요."}}),
	}
}

func (s *Store) normalize(t *Task) {
	t.Title = strings.TrimSpace(t.Title)
	if len([]rune(t.Title)) > 300 {
		t.Title = string([]rune(t.Title)[:300])
	}
	switch t.Bucket {
	case "day", "week", "someday":
	default:
		t.Bucket = "day"
	}
	if t.Bucket == "day" && !validDate(t.Date) {
		t.Date = Today()
	}
	if t.Bucket != "day" {
		t.Date = ""
		t.Alarm = ""
		t.Time = ""
	}
	if t.Bucket == "week" && !validDate(t.WeekOf) {
		t.WeekOf = weekStartOf(Today(), app0WeekStart())
	}
	if t.Bucket != "week" {
		t.WeekOf = ""
	}
	if !hhmm.MatchString(t.Time) {
		t.Time = ""
	}
	if !hhmm.MatchString(t.Alarm) {
		t.Alarm = ""
	}
	if !validDate(t.Due) {
		t.Due = ""
	}
	switch t.Repeat {
	case "", "daily", "weekdays", "weekly", "monthly":
	default:
		t.Repeat = ""
	}
	if t.Bucket == "someday" {
		t.Repeat = ""
	}
	if t.Bucket == "week" && t.Repeat != "" {
		t.Repeat = "weekly"
	}
	if t.Progress < 0 {
		t.Progress = 0
	}
	if t.Progress > 100 {
		t.Progress = 100
	}
	if t.Log == nil {
		t.Log = []LogEntry{}
	}
	if t.Cat != "" && s.cat(t.Cat) == nil {
		t.Cat = ""
	}
	if !t.Done {
		t.DoneAt = ""
	}
}

// app0WeekStart: 설정이 아직 없을 때(시험 등)는 월요일
func app0WeekStart() string {
	if app == nil {
		return "mon"
	}
	return app.Settings().WeekStart
}

func carryOn() bool {
	if app == nil {
		return true
	}
	return app.Settings().CarryOver
}

// ---------------------------------------------------------------- 날짜

func Today() string {
	if t := env("TODAY"); validDate(t) {
		return t
	}
	return time.Now().Format("2006-01-02")
}

func validDate(s string) bool {
	if len(s) != 10 {
		return false
	}
	_, err := time.ParseInLocation("2006-01-02", s, time.Local)
	return err == nil
}

func pd(s string) time.Time {
	t, _ := time.ParseInLocation("2006-01-02", s, time.Local)
	return t
}

func fd(t time.Time) string { return t.Format("2006-01-02") }

func addDays(s string, n int) string { return fd(pd(s).AddDate(0, 0, n)) }

func daysBetween(a, b string) int { return int(math.Round(pd(b).Sub(pd(a)).Hours() / 24)) }

func weekStartOf(date, ws string) string {
	t := pd(date)
	wd := int(t.Weekday()) // 일=0
	off := wd
	if ws != "sun" {
		off = (wd + 6) % 7
	}
	return fd(t.AddDate(0, 0, -off))
}

// nextOccurrence: 반복하는 일의 다음 차례 날짜
func nextOccurrence(date, rep string) string {
	t := pd(date)
	switch rep {
	case "daily":
		return fd(t.AddDate(0, 0, 1))
	case "weekdays":
		n := t.AddDate(0, 0, 1)
		for n.Weekday() == time.Saturday || n.Weekday() == time.Sunday {
			n = n.AddDate(0, 0, 1)
		}
		return fd(n)
	case "weekly":
		return fd(t.AddDate(0, 0, 7))
	case "monthly":
		// 같은 날짜, 그 달에 없으면 마지막 날 (1월 31일 → 2월 28일)
		y, m, d := t.Date()
		first := time.Date(y, m+1, 1, 0, 0, 0, 0, time.Local)
		last := first.AddDate(0, 1, -1).Day()
		if d > last {
			d = last
		}
		return fd(time.Date(first.Year(), first.Month(), d, 0, 0, 0, 0, time.Local))
	}
	return fd(t.AddDate(0, 0, 1))
}

// ---------------------------------------------------------------- 넘기기 · 반복

// rollover: 지난 날짜의 못 끝낸 일을 정리해요. 바뀐 것이 있으면 true.
func (s *Store) rollover(today string) bool {
	changed := false
	ws := app0WeekStart()
	thisWeek := weekStartOf(today, ws)
	for _, t := range s.d.Tasks {
		if t.Done {
			continue
		}
		switch t.Bucket {
		case "day":
			if t.Date >= today {
				continue
			}
			if t.Repeat != "" {
				old := t.Date
				d := t.Date
				for i := 0; d < today && i < 4000; i++ {
					d = nextOccurrence(d, t.Repeat)
				}
				if t.Due != "" {
					t.Due = addDays(t.Due, daysBetween(old, d))
				}
				t.Date, t.Progress, t.CarriedFrom = d, 0, ""
				changed = true
			} else if carryOn() {
				if t.CarriedFrom == "" {
					t.CarriedFrom = t.Date
				}
				t.Date = today
				changed = true
			}
		case "week":
			if addDays(t.WeekOf, 6) >= today {
				continue
			}
			if t.Repeat != "" {
				t.WeekOf, t.Progress = thisWeek, 0
				changed = true
			} else if carryOn() {
				if t.CarriedFrom == "" {
					t.CarriedFrom = t.WeekOf
				}
				t.WeekOf = thisWeek
				changed = true
			}
		}
	}
	return changed
}

// setDone: 끝냄 / 되돌림. 반복하는 일이면 다음 차례를 만들거나 지워요.
func (s *Store) setDone(t *Task, done bool) {
	if t.Done == done {
		return
	}
	now := time.Now().UnixMilli()
	t.Done = done
	t.Updated = now
	if done {
		t.DoneAt = Today()
		t.Progress = 100
		if t.Repeat != "" && (t.NextID == "" || s.task(t.NextID) == nil) {
			n := *t
			n.ID = randID(6)
			n.Done, n.DoneAt, n.Progress = false, "", 0
			n.Log = []LogEntry{}
			n.CarriedFrom, n.EventID, n.ReminderID, n.NextID = "", "", "", ""
			n.Created, n.Updated = now, now
			n.Order = float64(now)
			switch t.Bucket {
			case "day":
				n.Date = nextOccurrence(t.Date, t.Repeat)
				for i := 0; n.Date < Today() && i < 4000; i++ {
					n.Date = nextOccurrence(n.Date, t.Repeat)
				}
				if t.Due != "" {
					n.Due = addDays(t.Due, daysBetween(t.Date, n.Date))
				}
			case "week":
				n.WeekOf = addDays(t.WeekOf, 7)
			}
			s.d.Tasks = append(s.d.Tasks, &n)
			t.NextID = n.ID
		}
	} else {
		t.DoneAt = ""
		t.Progress = 0
		for _, l := range t.Log {
			t.Progress = l.Progress
			break
		}
		if t.NextID != "" {
			if n := s.task(t.NextID); n != nil && !n.Done && n.Updated == n.Created && len(n.Log) == 0 {
				s.remove(n.ID)
			}
			t.NextID = ""
		}
	}
}

// ---------------------------------------------------------------- 찾기 · 저장

func (s *Store) task(id string) *Task {
	for _, t := range s.d.Tasks {
		if t.ID == id {
			return t
		}
	}
	return nil
}

func (s *Store) cat(id string) *Category {
	for _, c := range s.d.Cats {
		if c.ID == id {
			return c
		}
	}
	return nil
}

func (s *Store) remove(id string) *Task {
	for i, t := range s.d.Tasks {
		if t.ID == id {
			s.d.Tasks = append(s.d.Tasks[:i], s.d.Tasks[i+1:]...)
			return t
		}
	}
	return nil
}

// commit: 바뀐 내용을 저장하고 위젯 파일도 새로 써요 (s.mu 를 잡은 채로 불러요)
func (s *Store) commit() {
	s.rev++
	s.save()
	s.exportWidget()
}

func (s *Store) save() {
	b, err := json.MarshalIndent(s.d, "", " ")
	if err != nil {
		log.Printf("save: %v", err)
		return
	}
	s.dailyBackup()
	writeFileAtomic(s.path(), b, 0o644)
}

// dailyBackup: 하루 한 번, 바뀌기 전 파일을 backups/data-<날짜>.json 으로 남겨요 (14개까지)
func (s *Store) dailyBackup() {
	dir := filepath.Join(s.dir, "backups")
	dst := filepath.Join(dir, "data-"+time.Now().Format("2006-01-02")+".json")
	if fileExists(dst) || !fileExists(s.path()) {
		return
	}
	os.MkdirAll(dir, 0o755)
	if b, err := os.ReadFile(s.path()); err == nil {
		os.WriteFile(dst, b, 0o644)
	}
	m, _ := filepath.Glob(filepath.Join(dir, "data-*.json"))
	sort.Strings(m)
	for len(m) > 14 {
		os.Remove(m[0])
		m = m[1:]
	}
}

func (s *Store) Flush() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.save()
}

func (s *Store) Rev() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.rev
}

func (s *Store) Today() string { return Today() }

// Tick: 날짜가 바뀌었는지 보고 정리해요 (켤 때 · 30초마다 · 설정이 바뀔 때)
func (s *Store) Tick() {
	s.mu.Lock()
	defer s.mu.Unlock()
	today := Today()
	changed := s.rollover(today)
	if s.d.LastDay != today {
		s.d.LastDay = today
		changed = true
	}
	if changed {
		s.commit()
	} else if s.lastExp != today {
		s.exportWidget()
	}
}

func (s *Store) loop() {
	for i := 0; ; i++ {
		time.Sleep(2 * time.Second)
		s.applyWidgetActions()
		if i%15 == 0 {
			s.Tick()
		}
	}
}

func (s *Store) Summary() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	open := 0
	for _, t := range s.d.Tasks {
		if !t.Done {
			open++
		}
	}
	return fmt.Sprintf("%d개 (남은 일 %d개) · 분류 %d개 · 마지막 정리 %s", len(s.d.Tasks), open, len(s.d.Cats), s.d.LastDay)
}

// ---------------------------------------------------------------- 화면에 보낼 상태

func (s *Store) stateLocked() map[string]any {
	cats := append([]*Category{}, s.d.Cats...)
	sort.SliceStable(cats, func(i, j int) bool { return cats[i].Order < cats[j].Order })
	// 끝낸 지 오래된 일(120일)은 화면에 보내지 않아요 (파일에는 남아 있어요)
	limit := addDays(Today(), -120)
	tasks := make([]*Task, 0, len(s.d.Tasks))
	for _, t := range s.d.Tasks {
		if t.Done && t.DoneAt != "" && t.DoneAt < limit {
			continue
		}
		tasks = append(tasks, t)
	}
	pal := map[string]map[string]string{}
	for k, v := range palette {
		pal[k] = map[string]string{"light": v[0], "dark": v[1]}
	}
	return map[string]any{"ok": true, "rev": s.rev, "today": Today(), "tasks": tasks, "cats": cats, "palette": pal}
}

func (s *Store) State() map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stateLocked()
}

// ---------------------------------------------------------------- 바꾸기

var errNoTask = errors.New("그 할 일을 찾지 못했어요. 화면을 새로 고쳐 볼게요")

// protected: 저장(save)으로는 바꾸지 않는 칸 (끝냄은 toggle, 링크는 links 로)
var protected = map[string]bool{"id": true, "created": true, "updated": true, "done": true, "doneAt": true, "nextId": true, "log": true, "eventId": true, "reminderId": true}

func (s *Store) Save(in map[string]json.RawMessage) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var id string
	if raw, ok := in["id"]; ok {
		json.Unmarshal(raw, &id)
	}
	now := time.Now().UnixMilli()
	t := s.task(id)
	if t == nil {
		// 새로 만들기 (지운 것을 되살릴 때는 id · 기록까지 그대로)
		nt := &Task{Bucket: "day", Date: Today(), Created: now, Order: float64(now)}
		b, _ := json.Marshal(in)
		if err := json.Unmarshal(b, nt); err != nil {
			return nil, errors.New("할 일 내용을 읽지 못했어요")
		}
		if nt.ID == "" || len(nt.ID) > 40 {
			nt.ID = randID(6)
		}
		if nt.Created == 0 {
			nt.Created = now
		}
		nt.Updated = now
		if nt.Created != now && nt.Updated == nt.Created {
			nt.Updated++
		}
		s.normalize(nt)
		if nt.Title == "" {
			return nil, errors.New("할 일 이름을 적어 주세요")
		}
		s.d.Tasks = append(s.d.Tasks, nt)
		s.commit()
		return nt, nil
	}
	cur, _ := json.Marshal(t)
	m := map[string]json.RawMessage{}
	json.Unmarshal(cur, &m)
	for k, v := range in {
		if protected[k] {
			continue
		}
		if _, ok := m[k]; ok {
			m[k] = v
		}
	}
	b, _ := json.Marshal(m)
	var nt Task
	if err := json.Unmarshal(b, &nt); err != nil {
		return nil, errors.New("할 일 내용을 읽지 못했어요")
	}
	s.normalize(&nt)
	if nt.Title == "" {
		return nil, errors.New("할 일 이름을 적어 주세요")
	}
	// 날짜를 직접 옮기면 '넘어옴' 표시는 지워요
	if nt.Bucket != t.Bucket || nt.Date != t.Date || nt.WeekOf != t.WeekOf {
		if _, ok := in["carriedFrom"]; !ok {
			nt.CarriedFrom = ""
		}
	}
	nt.Updated = now
	*t = nt
	s.commit()
	return t, nil
}

func (s *Store) Toggle(id string, done *bool) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t := s.task(id)
	if t == nil {
		return nil, errNoTask
	}
	want := !t.Done
	if done != nil {
		want = *done
	}
	s.setDone(t, want)
	s.commit()
	return t, nil
}

func (s *Store) Delete(id string) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t := s.remove(id)
	if t == nil {
		return nil, errNoTask
	}
	for _, o := range s.d.Tasks {
		if o.NextID == id {
			o.NextID = ""
		}
	}
	s.commit()
	return t, nil
}

func (s *Store) AddLog(id, text string, progress *int) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t := s.task(id)
	if t == nil {
		return nil, errNoTask
	}
	text = strings.TrimSpace(text)
	if progress != nil {
		t.Progress = max(0, min(100, *progress))
	}
	if text != "" {
		if len([]rune(text)) > 2000 {
			text = string([]rune(text)[:2000])
		}
		t.Log = append([]LogEntry{{Date: Today(), Text: text, Progress: t.Progress}}, t.Log...)
	}
	t.Updated = time.Now().UnixMilli()
	s.commit()
	return t, nil
}

func (s *Store) DelLog(id string, i int) (*Task, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t := s.task(id)
	if t == nil {
		return nil, errNoTask
	}
	if i >= 0 && i < len(t.Log) {
		t.Log = append(t.Log[:i], t.Log[i+1:]...)
	}
	t.Updated = time.Now().UnixMilli()
	s.commit()
	return t, nil
}

// Links: 캘린더 일정 · 미리 알림 번호만 바꿔요 (손댄 시각은 그대로)
func (s *Store) Links(items []struct {
	ID         string  `json:"id"`
	EventID    *string `json:"eventId"`
	ReminderID *string `json:"reminderId"`
}) {
	s.mu.Lock()
	defer s.mu.Unlock()
	changed := false
	for _, it := range items {
		t := s.task(it.ID)
		if t == nil {
			continue
		}
		if it.EventID != nil && t.EventID != *it.EventID {
			t.EventID = *it.EventID
			changed = true
		}
		if it.ReminderID != nil && t.ReminderID != *it.ReminderID {
			t.ReminderID = *it.ReminderID
			changed = true
		}
	}
	if changed {
		s.commit()
	}
}

// Import: 아이폰 '미리 알림'의 DayROAD 목록에 새로 생긴 것을 가져와요
func (s *Store) Import(items []struct {
	Title      string `json:"title"`
	Due        string `json:"due"`
	Time       string `json:"time"`
	Note       string `json:"note"`
	ReminderID string `json:"reminderId"`
}) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now().UnixMilli()
	n := 0
	for i, it := range items {
		if it.ReminderID == "" || strings.TrimSpace(it.Title) == "" {
			continue
		}
		dup := false
		for _, t := range s.d.Tasks {
			if t.ReminderID == it.ReminderID {
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		t := &Task{ID: randID(6), Title: it.Title, Note: it.Note, ReminderID: it.ReminderID, Bucket: "day", Date: Today(),
			Time: it.Time, Created: now, Updated: now, Order: float64(now + int64(i))}
		if validDate(it.Due) {
			if it.Due >= Today() {
				t.Date = it.Due
			}
		} else {
			t.Bucket = "someday"
		}
		s.normalize(t)
		s.d.Tasks = append(s.d.Tasks, t)
		n++
	}
	if n > 0 {
		s.commit()
	}
	return n
}

func (s *Store) SaveCat(c Category) (*Category, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	c.Name = strings.TrimSpace(c.Name)
	if c.Name == "" {
		return nil, errors.New("분류 이름을 적어 주세요")
	}
	if len([]rune(c.Name)) > 20 {
		c.Name = string([]rune(c.Name)[:20])
	}
	if _, ok := palette[c.Color]; !ok {
		c.Color = "slate"
	}
	for _, o := range s.d.Cats {
		if o.ID != c.ID && o.Name == c.Name {
			return nil, errors.New("같은 이름의 분류가 이미 있어요")
		}
	}
	if cur := s.cat(c.ID); cur != nil {
		cur.Name, cur.Color = c.Name, c.Color
		s.commit()
		return cur, nil
	}
	c.ID = randID(5)
	c.Order = len(s.d.Cats)
	for _, o := range s.d.Cats {
		if o.Order >= c.Order {
			c.Order = o.Order + 1
		}
	}
	s.d.Cats = append(s.d.Cats, &c)
	s.commit()
	return &c, nil
}

func (s *Store) DeleteCat(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, c := range s.d.Cats {
		if c.ID == id {
			s.d.Cats = append(s.d.Cats[:i], s.d.Cats[i+1:]...)
			for _, t := range s.d.Tasks {
				if t.Cat == id {
					t.Cat = ""
				}
			}
			s.commit()
			return nil
		}
	}
	return errors.New("그 분류를 찾지 못했어요")
}

func (s *Store) OrderCats(ids []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, id := range ids {
		if c := s.cat(id); c != nil {
			c.Order = i
		}
	}
	s.commit()
}

// ---------------------------------------------------------------- 주소

func (a *App) storeRoutes(api func(string, http.HandlerFunc)) {
	st := a.store
	reply := func(w http.ResponseWriter, extra map[string]any) {
		s := st.State()
		for k, v := range extra {
			s[k] = v
		}
		writeJSON(w, s)
	}
	fail := func(w http.ResponseWriter, err error) { jsonError(w, 400, err.Error()) }

	api("/api/state", func(w http.ResponseWriter, r *http.Request) {
		st.Tick()
		reply(w, nil)
	})
	api("/api/task/save", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Task map[string]json.RawMessage `json:"task"`
		}
		if err := readJSON(r, &in); err != nil || in.Task == nil {
			fail(w, errors.New("할 일 내용을 읽지 못했어요"))
			return
		}
		t, err := st.Save(in.Task)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"task": t})
	})
	api("/api/task/toggle", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			ID   string `json:"id"`
			Done *bool  `json:"done"`
		}
		readJSON(r, &in)
		t, err := st.Toggle(in.ID, in.Done)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"task": t})
	})
	api("/api/task/delete", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			ID string `json:"id"`
		}
		readJSON(r, &in)
		t, err := st.Delete(in.ID)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"deleted": t})
	})
	api("/api/task/log", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			ID       string `json:"id"`
			Text     string `json:"text"`
			Progress *int   `json:"progress"`
		}
		readJSON(r, &in)
		t, err := st.AddLog(in.ID, in.Text, in.Progress)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"task": t})
	})
	api("/api/task/logdel", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			ID string `json:"id"`
			I  int    `json:"i"`
		}
		readJSON(r, &in)
		t, err := st.DelLog(in.ID, in.I)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"task": t})
	})
	api("/api/links", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Items []struct {
				ID         string  `json:"id"`
				EventID    *string `json:"eventId"`
				ReminderID *string `json:"reminderId"`
			} `json:"items"`
		}
		readJSON(r, &in)
		st.Links(in.Items)
		reply(w, nil)
	})
	api("/api/sync/done", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			IDs []string `json:"ids"`
		}
		readJSON(r, &in)
		st.mu.Lock()
		n := 0
		for _, id := range in.IDs {
			if t := st.task(id); t != nil && !t.Done {
				st.setDone(t, true)
				n++
			}
		}
		if n > 0 {
			st.commit()
		}
		st.mu.Unlock()
		reply(w, map[string]any{"count": n})
	})
	api("/api/import", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Items []struct {
				Title      string `json:"title"`
				Due        string `json:"due"`
				Time       string `json:"time"`
				Note       string `json:"note"`
				ReminderID string `json:"reminderId"`
			} `json:"items"`
		}
		readJSON(r, &in)
		n := st.Import(in.Items)
		reply(w, map[string]any{"count": n})
	})
	api("/api/cat/save", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Cat Category `json:"cat"`
		}
		readJSON(r, &in)
		c, err := st.SaveCat(in.Cat)
		if err != nil {
			fail(w, err)
			return
		}
		reply(w, map[string]any{"cat": c})
	})
	api("/api/cat/delete", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			ID string `json:"id"`
		}
		readJSON(r, &in)
		if err := st.DeleteCat(in.ID); err != nil {
			fail(w, err)
			return
		}
		reply(w, nil)
	})
	api("/api/cat/order", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			IDs []string `json:"ids"`
		}
		readJSON(r, &in)
		st.OrderCats(in.IDs)
		reply(w, nil)
	})
}

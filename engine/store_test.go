package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestStore(t *testing.T, today string) *Store {
	t.Helper()
	t.Setenv("DAYROAD_TODAY", today)
	dir := t.TempDir()
	return NewStore(dir)
}

func raw(m map[string]any) map[string]json.RawMessage {
	out := map[string]json.RawMessage{}
	for k, v := range m {
		b, _ := json.Marshal(v)
		out[k] = b
	}
	return out
}

func TestSeedAndSave(t *testing.T) {
	s := newTestStore(t, "2026-11-10")
	if len(s.d.Tasks) != 3 || len(s.d.Cats) != 4 {
		t.Fatalf("seed: %d tasks %d cats", len(s.d.Tasks), len(s.d.Cats))
	}
	tk, err := s.Save(raw(map[string]any{"title": "  보고서 초안 쓰기 ", "cat": "work", "due": "2026-11-13", "time": "14:00", "alarm": "13:45"}))
	if err != nil {
		t.Fatal(err)
	}
	if tk.Title != "보고서 초안 쓰기" || tk.Date != "2026-11-10" || tk.Bucket != "day" || tk.Alarm != "13:45" {
		t.Fatalf("bad task %+v", tk)
	}
	if _, err := s.Save(raw(map[string]any{"title": "   "})); err == nil {
		t.Fatal("empty title should fail")
	}
	// 고치기: 보호된 칸은 그대로
	tk2, err := s.Save(raw(map[string]any{"id": tk.ID, "title": "보고서", "done": true, "progress": 140, "cat": "nope", "time": "25:00"}))
	if err != nil {
		t.Fatal(err)
	}
	if tk2.Done || tk2.Progress != 100 || tk2.Cat != "" || tk2.Time != "" || tk2.Title != "보고서" {
		t.Fatalf("update normalize %+v", tk2)
	}
	// 다시 불러와도 같아요
	s2 := NewStore(s.dir)
	if s2.task(tk.ID) == nil || s2.task(tk.ID).Title != "보고서" {
		t.Fatal("not persisted")
	}
}

func TestCarryOver(t *testing.T) {
	s := newTestStore(t, "2026-11-09")
	a, _ := s.Save(raw(map[string]any{"title": "우유 사기"}))
	b, _ := s.Save(raw(map[string]any{"title": "보고서", "progress": 60}))
	s.AddLog(b.ID, "1장까지 씀", nil)
	done, _ := s.Save(raw(map[string]any{"title": "은행"}))
	s.Toggle(done.ID, nil)
	w, _ := s.Save(raw(map[string]any{"title": "책 읽기", "bucket": "week"}))
	if w.WeekOf != "2026-11-09" {
		t.Fatalf("weekOf %s", w.WeekOf)
	}

	os.Setenv("DAYROAD_TODAY", "2026-11-10")
	s.Tick()
	if a.Date != "2026-11-10" || a.CarriedFrom != "2026-11-09" {
		t.Fatalf("carry a: %+v", a)
	}
	if b.Progress != 60 || len(b.Log) != 1 {
		t.Fatalf("carry keeps progress/log: %+v", b)
	}
	if done.Date != "2026-11-09" {
		t.Fatal("done task must stay")
	}
	// 이틀 더 지나도 처음 날짜를 기억해요
	os.Setenv("DAYROAD_TODAY", "2026-11-12")
	s.Tick()
	if a.Date != "2026-11-12" || a.CarriedFrom != "2026-11-09" {
		t.Fatalf("carry again: %+v", a)
	}
	// 다음 주로 넘어가면 '이번 주 안에'도 넘어와요
	os.Setenv("DAYROAD_TODAY", "2026-11-16")
	s.Tick()
	if w.WeekOf != "2026-11-16" || w.CarriedFrom != "2026-11-09" {
		t.Fatalf("week carry: %+v", w)
	}
	// 날짜를 직접 옮기면 넘어옴 표시는 지워요
	s.Save(raw(map[string]any{"id": a.ID, "date": "2026-11-20"}))
	if a.CarriedFrom != "" {
		t.Fatal("moving clears carriedFrom")
	}
}

func TestNoCarryWhenOff(t *testing.T) {
	s := newTestStore(t, "2026-11-09")
	a, _ := s.Save(raw(map[string]any{"title": "우유 사기"}))
	app = &App{support: s.dir, settings: defaultSettings()}
	app.settings.CarryOver = false
	defer func() { app = nil }()
	os.Setenv("DAYROAD_TODAY", "2026-11-10")
	s.Tick()
	if a.Date != "2026-11-09" {
		t.Fatalf("should stay: %+v", a)
	}
}

func TestRepeat(t *testing.T) {
	s := newTestStore(t, "2026-11-10") // 화요일
	d, _ := s.Save(raw(map[string]any{"title": "운동 30분", "repeat": "daily"}))
	wk, _ := s.Save(raw(map[string]any{"title": "주간 회의", "repeat": "weekly", "due": "2026-11-11"}))
	s.Toggle(d.ID, nil)
	n := s.task(d.NextID)
	if n == nil || n.Date != "2026-11-11" || n.Done || n.Repeat != "daily" {
		t.Fatalf("next daily %+v", n)
	}
	// 되돌리면 손대지 않은 다음 차례는 지워요
	s.Toggle(d.ID, nil)
	if s.task(n.ID) != nil || d.NextID != "" {
		t.Fatal("unspawn")
	}
	// 놓친 반복은 넘기지 않고 다음 차례로
	os.Setenv("DAYROAD_TODAY", "2026-11-19")
	s.Tick()
	if wk.Date != "2026-11-24" || wk.CarriedFrom != "" || wk.Due != "2026-11-25" {
		t.Fatalf("weekly skip %+v", wk)
	}
	if d.Date != "2026-11-19" {
		t.Fatalf("daily skip %+v", d)
	}
}

func TestNextOccurrence(t *testing.T) {
	cases := [][3]string{
		{"2026-01-31", "monthly", "2026-02-28"},
		{"2026-11-13", "weekdays", "2026-11-16"}, // 금 → 월
		{"2026-11-10", "weekly", "2026-11-17"},
		{"2026-12-31", "daily", "2027-01-01"},
	}
	for _, c := range cases {
		if got := nextOccurrence(c[0], c[1]); got != c[2] {
			t.Errorf("%s %s → %s, want %s", c[0], c[1], got, c[2])
		}
	}
	if weekStartOf("2026-11-15", "mon") != "2026-11-09" || weekStartOf("2026-11-15", "sun") != "2026-11-15" {
		t.Error("weekStartOf")
	}
}

func TestDeleteRestoreAndCats(t *testing.T) {
	s := newTestStore(t, "2026-11-10")
	tk, _ := s.Save(raw(map[string]any{"title": "치과", "cat": "health"}))
	s.AddLog(tk.ID, "예약 전화함", intp(30))
	del, err := s.Delete(tk.ID)
	if err != nil || s.task(tk.ID) != nil {
		t.Fatal("delete")
	}
	b, _ := json.Marshal(del)
	var m map[string]json.RawMessage
	json.Unmarshal(b, &m)
	back, err := s.Save(m)
	if err != nil || back.ID != tk.ID || len(back.Log) != 1 || back.Progress != 30 {
		t.Fatalf("restore %+v %v", back, err)
	}
	c, err := s.SaveCat(Category{Name: "운동", Color: "teal"})
	if err != nil || c.ID == "" {
		t.Fatal(err)
	}
	if _, err := s.SaveCat(Category{Name: "운동"}); err == nil {
		t.Fatal("dup name")
	}
	s.Save(raw(map[string]any{"id": tk.ID, "cat": c.ID}))
	s.DeleteCat(c.ID)
	if back.Cat != "" {
		t.Fatal("cat delete clears tasks")
	}
}

func intp(i int) *int { return &i }

func TestWidgetExportAndActions(t *testing.T) {
	s := newTestStore(t, "2026-11-10")
	a, _ := s.Save(raw(map[string]any{"title": "회의 자료", "time": "09:30", "cat": "work", "due": "2026-11-12"}))
	s.Save(raw(map[string]any{"title": "다음 주 일", "date": "2026-11-17"}))
	var w widgetData
	b, err := os.ReadFile(filepath.Join(s.dir, "widget", "widget.json"))
	if err != nil {
		t.Fatal(err)
	}
	json.Unmarshal(b, &w)
	if w.Total != 4 || w.Items[0].ID != a.ID || w.Items[0].Badge != "D-2" || w.Items[0].Color != "#3366B0" || w.Dow != "화요일" {
		t.Fatalf("widget %+v", w)
	}
	if len(w.Week) != 7 || !w.Week[1].Today || w.Week[1].Total != 4 || !strings.HasPrefix(w.WeekLabel, "11월 9일") {
		t.Fatalf("week %+v %s", w.Week, w.WeekLabel)
	}
	os.WriteFile(filepath.Join(s.dir, "widget", "actions.jsonl"), []byte(`{"id":"`+a.ID+`","done":true}`+"\n"+`{"id":"nope","done":true}`+"\n"), 0o644)
	s.applyWidgetActions()
	if !a.Done {
		t.Fatal("widget action not applied")
	}
	b, _ = os.ReadFile(filepath.Join(s.dir, "widget", "widget.json"))
	json.Unmarshal(b, &w)
	if w.Done != 1 {
		t.Fatalf("widget done %d", w.Done)
	}
}

func TestImport(t *testing.T) {
	s := newTestStore(t, "2026-11-10")
	items := []struct {
		Title      string `json:"title"`
		Due        string `json:"due"`
		Time       string `json:"time"`
		Note       string `json:"note"`
		ReminderID string `json:"reminderId"`
	}{{Title: "아이폰에서 적은 일", Due: "2026-11-12", ReminderID: "r1"}, {Title: "날짜 없음", ReminderID: "r2"}}
	if n := s.Import(items); n != 2 {
		t.Fatalf("import %d", n)
	}
	if n := s.Import(items); n != 0 {
		t.Fatal("dup import")
	}
}

func TestEditLog(t *testing.T) {
	s := newTestStore(t, "2026-11-09")
	tk, _ := s.Save(raw(map[string]any{"title": "보고서"}))
	s.AddLog(tk.ID, "1장까지 씀", intp(25))
	s.AddLog(tk.ID, "2장까지 씀", intp(50))
	got, err := s.EditLog(tk.ID, 1, "  1장 · 표까지 씀  ")
	if err != nil {
		t.Fatal(err)
	}
	if got.Log[1].Text != "1장 · 표까지 씀" || got.Log[1].Progress != 25 || got.Log[0].Text != "2장까지 씀" {
		t.Fatalf("edit log %+v", got.Log)
	}
	if _, err := s.EditLog(tk.ID, 0, "   "); err == nil || s.task(tk.ID).Log[0].Text != "2장까지 씀" {
		t.Fatal("empty text must not change the log")
	}
	if _, err := s.EditLog(tk.ID, 5, "x"); err == nil {
		t.Fatal("out of range should fail")
	}
	s2 := NewStore(s.dir)
	if s2.task(tk.ID).Log[1].Text != "1장 · 표까지 씀" {
		t.Fatal("edited log not persisted")
	}
}

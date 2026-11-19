package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func cloudFile(t *testing.T, root string) storeData {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, "DayROAD", "data.json"))
	if err != nil {
		t.Fatalf("iCloud 파일 없음: %v", err)
	}
	var d storeData
	if err := json.Unmarshal(b, &d); err != nil {
		t.Fatal(err)
	}
	return d
}

func hasTitle(d storeData, title string) bool {
	for _, t := range d.Tasks {
		if t.Title == title {
			return true
		}
	}
	return false
}

func tick() { time.Sleep(3 * time.Millisecond) }

// 처음 켤 때 지금 자료가 iCloud 로 옮겨지고, 옮기기 전 백업이 남아요
func TestCloudMigrate(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	s := newTestStore(t, "2026-11-19")
	s.Save(raw(map[string]any{"title": "기존 할 일"}))
	// 아직 맞추기 전에는 iCloud 에 쓰지 않아요
	if fileExists(filepath.Join(root, "DayROAD", "data.json")) {
		t.Fatal("맞추기 전에 iCloud 에 썼어요")
	}
	s.CloudSync()
	if s.cloud.State != "ok" || s.cloud.Moved == 0 {
		t.Fatalf("state %+v", s.cloud)
	}
	d := cloudFile(t, root)
	if !hasTitle(d, "기존 할 일") || len(d.Tasks) != 4 || len(d.Cats) != 4 {
		t.Fatalf("옮긴 자료가 달라요: %d tasks", len(d.Tasks))
	}
	if m, _ := filepath.Glob(filepath.Join(s.dir, "backups", "before-icloud-*.json")); len(m) != 1 {
		t.Fatal("옮기기 전 백업이 없어요")
	}
	if !fileExists(s.path()) {
		t.Fatal("맥 안의 자료가 없어졌어요")
	}
	// 그다음 바꾼 것도 iCloud 에 바로 써요
	s.Save(raw(map[string]any{"title": "새 할 일"}))
	if !hasTitle(cloudFile(t, root), "새 할 일") {
		t.Fatal("바꾼 것이 iCloud 에 안 갔어요")
	}
	// 같은 내용이면 다시 쓰지 않아요
	st1, _ := os.Stat(filepath.Join(root, "DayROAD", "data.json"))
	time.Sleep(20 * time.Millisecond)
	s.CloudSync()
	st2, _ := os.Stat(filepath.Join(root, "DayROAD", "data.json"))
	if !st1.ModTime().Equal(st2.ModTime()) {
		t.Fatal("바뀐 게 없는데 다시 썼어요")
	}
}

// 두 기기(맥 A · 새로 깐 맥 B)가 같은 iCloud 파일을 써요
func TestCloudTwoDevices(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	a := newTestStore(t, "2026-11-19")
	keep, _ := a.Save(raw(map[string]any{"title": "A 의 할 일"}))
	gone, _ := a.Save(raw(map[string]any{"title": "지울 할 일"}))
	a.SaveCat(Category{Name: "사역", Color: "teal"})
	a.CloudSync()

	b := newTestStore(t, "2026-11-19")
	b.CloudSync()
	if len(b.d.Tasks) != len(a.d.Tasks) || b.task(keep.ID) == nil || len(b.d.Cats) != 5 {
		t.Fatalf("B 가 A 자료를 그대로 받지 못했어요: %d vs %d tasks, %d cats", len(b.d.Tasks), len(a.d.Tasks), len(b.d.Cats))
	}
	if !fileExists(b.path()) {
		t.Fatal("B 맥 안에 저장 안 됨")
	}

	// B 에서 추가 · 고치기, A 에서 지우기
	tick()
	b.Save(raw(map[string]any{"title": "B 에서 적은 일"}))
	tick()
	b.AddLog(keep.ID, "B 에서 남긴 기록", nil)
	tick()
	a.Delete(gone.ID)
	a.CloudSync()
	b.CloudSync()
	a.CloudSync()
	for _, s := range []*Store{a, b} {
		if s.task(gone.ID) != nil {
			t.Fatal("지운 할 일이 되살아났어요")
		}
		if k := s.task(keep.ID); k == nil || len(k.Log) != 1 {
			t.Fatal("B 의 기록이 A 에 오지 않았어요")
		}
		found := false
		for _, x := range s.d.Tasks {
			found = found || x.Title == "B 에서 적은 일"
		}
		if !found {
			t.Fatal("B 에서 적은 일이 없어요")
		}
	}
	if len(a.d.Tasks) != len(b.d.Tasks) {
		t.Fatalf("A %d · B %d", len(a.d.Tasks), len(b.d.Tasks))
	}

	// 둘 다 같은 할 일을 고치면 나중에 고친 쪽
	tick()
	a.Save(raw(map[string]any{"id": keep.ID, "title": "A 가 고침"}))
	tick()
	b.Save(raw(map[string]any{"id": keep.ID, "title": "B 가 나중에 고침"}))
	a.CloudSync()
	b.CloudSync()
	a.CloudSync()
	if a.task(keep.ID).Title != "B 가 나중에 고침" || b.task(keep.ID).Title != "B 가 나중에 고침" {
		t.Fatalf("나중에 고친 쪽이 아니에요: %q / %q", a.task(keep.ID).Title, b.task(keep.ID).Title)
	}

	// 분류 지우기도 따라가요
	tick()
	a.DeleteCat(a.d.Cats[len(a.d.Cats)-1].ID)
	a.CloudSync()
	b.CloudSync()
	if len(b.d.Cats) != 4 {
		t.Fatalf("분류 지우기가 B 에 안 감: %d", len(b.d.Cats))
	}

	// 다시 켜도(새 Store) 같아요
	a2 := NewStore(a.dir)
	if len(a2.d.Tasks) != len(a.d.Tasks) || a2.d.Deleted[gone.ID] == 0 {
		t.Fatal("다시 불러온 자료가 달라요")
	}
}

// iCloud 가 만든 충돌 사본은 합친 뒤 지워요
func TestCloudConflictCopy(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	s := newTestStore(t, "2026-11-19")
	s.CloudSync()
	d := cloudFile(t, root)
	now := time.Now().UnixMilli() + 10
	d.Tasks = append(d.Tasks, &Task{ID: "phone1", Title: "아이폰에서 적은 일", Bucket: "day", Date: "2026-11-19", Created: now, Updated: now})
	b, _ := json.Marshal(d)
	cp := filepath.Join(root, "DayROAD", "data 2.json")
	os.WriteFile(cp, b, 0o644)
	s.CloudSync()
	if s.task("phone1") == nil {
		t.Fatal("충돌 사본의 할 일을 못 합쳤어요")
	}
	if fileExists(cp) {
		t.Fatal("충돌 사본이 남아 있어요")
	}
	if !hasTitle(cloudFile(t, root), "아이폰에서 적은 일") {
		t.Fatal("합친 결과가 iCloud 에 없어요")
	}
}

// 망가진(받는 중인) 파일은 덮어쓰지 않아요 · 설정에서 끄면 쓰지 않아요
func TestCloudBrokenAndOff(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	os.MkdirAll(filepath.Join(root, "DayROAD"), 0o755)
	p := filepath.Join(root, "DayROAD", "data.json")
	os.WriteFile(p, []byte(`{"v":1,"tasks":[`), 0o644)
	s := newTestStore(t, "2026-11-19")
	s.CloudSync()
	s.Save(raw(map[string]any{"title": "x"}))
	if b, _ := os.ReadFile(p); string(b) != `{"v":1,"tasks":[` || s.cloud.State != "waiting" {
		t.Fatalf("망가진 파일을 덮어썼어요 (%s)", s.cloud.State)
	}
	// iCloud 쪽 아직 안 내려온 파일(.icloud)만 있으면 기다려요
	os.Remove(p)
	os.WriteFile(filepath.Join(root, "DayROAD", ".data.json.icloud"), []byte("x"), 0o644)
	s.CloudSync()
	if fileExists(p) || s.cloud.State != "waiting" {
		t.Fatal("내려받기 전에 덮어썼어요")
	}
	// iCloud Drive 가 없는 맥
	t.Setenv("DAYROAD_ICLOUD", filepath.Join(root, "없음"))
	s.CloudSync()
	if s.cloud.State != "nodrive" {
		t.Fatalf("state %s", s.cloud.State)
	}
}

// 한 주의 시작: 나중에 바꾼 쪽을 따르고, '이번 주 안에' 할 일의 첫날도 맞춰요
func TestCloudWeekStart(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	a := newTestStore(t, "2026-11-19")
	if a.d.WeekStart != "mon" { // 시험에서는 설정이 없으면 월요일
		t.Fatalf("처음 값 %q", a.d.WeekStart)
	}
	wk, _ := a.Save(raw(map[string]any{"title": "이번 주 안에 할 일", "bucket": "week", "weekOf": "2026-11-16"}))
	a.CloudSync()
	b := newTestStore(t, "2026-11-19")
	b.CloudSync()
	tick()
	// B(아이폰이라 치고)에서 일요일로 바꿔요 — app 이 없는 시험이라 rollover 는 월요일 기준이니 맞추기만 봐요
	b.SetWeekStart("sun")
	if b.d.WeekStartAt == 0 || b.d.WeekStart != "sun" {
		t.Fatal("바꾼 시각이 없어요")
	}
	a.CloudSync()
	if a.d.WeekStart != "sun" {
		t.Fatalf("A 가 따라가지 않았어요: %q", a.d.WeekStart)
	}
	if weekStartOf("2026-11-16", "sun") != "2026-11-15" || a.task(wk.ID) == nil {
		t.Fatal("주 첫날 계산")
	}
}

// updated 가 같은데 내용이 다르면(맥만 캘린더 연결 번호를 가진 경우) 두 기기가 같은 쪽을 골라서 더 쓰지 않아요
func TestCloudTieNoPingPong(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DAYROAD_ICLOUD", root)
	a := newTestStore(t, "2026-11-19")
	tk, _ := a.Save(raw(map[string]any{"title": "같은 시각"}))
	a.CloudSync()
	b := newTestStore(t, "2026-11-19")
	b.CloudSync()
	ev := "EV1"
	a.Links([]struct {
		ID         string  `json:"id"`
		EventID    *string `json:"eventId"`
		ReminderID *string `json:"reminderId"`
	}{{ID: tk.ID, EventID: &ev}})
	for i := 0; i < 3; i++ {
		a.CloudSync()
		b.CloudSync()
	}
	if a.task(tk.ID).EventID != b.task(tk.ID).EventID {
		t.Fatal("두 기기가 다른 쪽을 골랐어요")
	}
	p := filepath.Join(root, "DayROAD", "data.json")
	st1, _ := os.Stat(p)
	time.Sleep(20 * time.Millisecond)
	a.CloudSync()
	b.CloudSync()
	st2, _ := os.Stat(p)
	if !st1.ModTime().Equal(st2.ModTime()) {
		t.Fatal("서로 계속 다시 써요")
	}
}

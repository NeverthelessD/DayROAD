package main

// iCloud Drive 저장 (v1.4.0)
//
// 할 일 파일을 'iCloud Drive › DayROAD › data.json' 에도 저장해요. 아이폰 DayROAD(만들 예정) · 다른 맥이 같은 파일을 봐요.
// 맥 안의 Support/data.json 은 그대로 '일하는 사본'이에요(하루 백업도 그대로). 두 파일은 6초마다 맞춰요.
//
// 처음(이 버전으로 처음 켤 때): iCloud 에 파일이 없으면 지금 자료를 그대로 옮겨요(복사, 맥 안의 것은 남겨 둠).
//   옮기기 전 자료는 backups/before-icloud-<날짜>.json 에 따로 남겨요.
//   새로 깐 맥(자료 없음)에서 켰는데 iCloud 에 파일이 있으면, 처음 안내용 할 일은 버리고 iCloud 자료를 그대로 받아요.
// 맞추는 규칙(merge) — 아이폰 앱도 같은 규칙을 써야 해요:
//   - 할 일: id 마다 updated 가 큰 쪽. 같으면 JSON 글자를 비교해 큰 쪽(어느 기기에서 해도 같은 답이 나오게).
//   - 지운 할 일: deleted[id] = 지운 시각. 그 시각 이전에 마지막으로 고친 할 일은 지워요. 60일 지나면 잊어요.
//   - 분류 목록: catsUpdated 가 큰 쪽을 통째로 (같으면 JSON 비교).
//   - lastDay: 큰 쪽.
// iCloud 가 충돌 사본(data 2.json 등)을 만들면 함께 합친 뒤 지워요.
// 받는 쪽이 이미 같은 내용이면 다시 쓰지 않아요(두 기기가 서로 계속 다시 쓰지 않게).

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io/fs"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type cloudState struct {
	State  string // off | nodrive | denied | waiting | error | ok
	Msg    string
	Dir    string
	Last   int64 // 마지막으로 맞춘 시각 (ms)
	Moved  int64 // 이번에 처음 옮긴 시각 (ms)
	synced bool  // 이번 실행에서 한 번이라도 맞췄는지 (그 전에는 iCloud 에 쓰지 않아요)

	seenMod  time.Time
	seenSize int64
	lastHash [32]byte
}

const tombstoneDays = 60

// cloudRoot: iCloud Drive 자리. 시험에서는 DAYROAD_ICLOUD 로 바꿔요.
func cloudRoot() string {
	if d := env("ICLOUD"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Mobile Documents", "com~apple~CloudDocs")
}

func cloudOn() bool {
	if app == nil {
		return env("ICLOUD") != ""
	}
	return app.Settings().ICloud
}

func canon(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

// CloudSync: 지금 맞춰요 (6초마다 · '지금 맞추기' 단추)
func (s *Store) CloudSync() {
	if cloudOn() && !s.probeCloud() {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	st, moved := s.cloud.State, s.cloud.Moved
	s.cloudSyncLocked()
	if s.cloud.State != st || s.cloud.Moved != moved {
		s.rev++ // 화면이 새 상태를 받아 가게
	}
}

// probeCloud: 자물쇠를 잡기 전에 iCloud Drive 를 한 번 건드려 봐요.
// 처음에는 맥이 'iCloud Drive 파일에 접근하려고 합니다' 허락을 물으면서 파일 작업이 멈출 수 있어요.
// 그동안 앱 전체가 멈추지 않게, 3초 안에 끝나지 않으면 이번에는 건너뛰어요(허락하면 다음 차례에 맞춰요).
func (s *Store) probeCloud() bool {
	if !s.probing.CompareAndSwap(false, true) {
		return false
	}
	done := make(chan struct{})
	go func() {
		defer s.probing.Store(false)
		defer close(done)
		root := cloudRoot()
		if _, err := os.Stat(root); err == nil {
			os.ReadDir(filepath.Join(root, "DayROAD"))
		}
	}()
	select {
	case <-done:
		return true
	case <-time.After(3 * time.Second):
		s.mu.Lock()
		if s.cloud.State != "asking" {
			log.Printf("iCloud: 파일 작업이 3초 넘게 멈춤 — 맥이 허락을 묻는 중일 수 있어요")
			s.rev++
		}
		s.cloud.State, s.cloud.Msg = "asking", "맥이 iCloud Drive 를 써도 되는지 묻고 있어요. '허용'을 눌러 주세요"
		s.mu.Unlock()
		return false
	}
}

func (s *Store) cloudFail(err error, what string) {
	c := &s.cloud
	if errors.Is(err, fs.ErrPermission) {
		if c.State != "denied" {
			log.Printf("iCloud: 접근 허락 없음 (%s): %v", what, err)
		}
		c.State, c.Msg = "denied", "맥 설정에서 DayROAD 가 iCloud Drive 를 쓸 수 있게 허락해 주세요"
		return
	}
	if c.State != "error" || !strings.Contains(c.Msg, what) {
		log.Printf("iCloud: %s 실패: %v", what, err)
	}
	c.State, c.Msg = "error", "iCloud Drive 에 "+what+" 못했어요. 잠시 뒤 다시 해 볼게요"
}

func (s *Store) cloudSyncLocked() {
	c := &s.cloud
	if !cloudOn() {
		c.State, c.Msg, c.synced = "off", "", false
		return
	}
	root := cloudRoot()
	if st, err := os.Stat(root); err != nil || !st.IsDir() {
		if err != nil && errors.Is(err, fs.ErrPermission) {
			s.cloudFail(err, "들어가지")
			return
		}
		c.State, c.Msg, c.synced = "nodrive", "이 맥에서 iCloud Drive 가 켜져 있지 않아요", false
		return
	}
	dir := filepath.Join(root, "DayROAD")
	c.Dir = dir
	if err := os.MkdirAll(dir, 0o755); err != nil {
		s.cloudFail(err, "폴더를 만들지")
		return
	}
	p := filepath.Join(dir, "data.json")
	st, err := os.Stat(p)
	if errors.Is(err, fs.ErrNotExist) {
		// 맥에 아직 내려받지 않은 파일(.data.json.icloud)이면 기다려요 — 덮어쓰면 안 돼요
		if fileExists(filepath.Join(dir, ".data.json.icloud")) {
			c.State, c.Msg = "waiting", "iCloud 에서 할 일 파일을 내려받는 중이에요"
			if runtime.GOOS == "darwin" {
				exec.Command("/usr/bin/brctl", "download", p).Start()
			}
			return
		}
		// 처음: 지금 자료를 iCloud 로 옮겨요
		s.backupAs("before-icloud")
		if err := s.cloudWrite(canonIndent(&s.d)); err != nil {
			s.cloudFail(err, "옮기지")
			return
		}
		now := time.Now().UnixMilli()
		c.State, c.Msg, c.synced, c.Last, c.Moved = "ok", "", true, now, now
		s.fresh = false
		log.Printf("iCloud: 할 일 %d개 · 분류 %d개를 %s 로 옮겼어요", len(s.d.Tasks), len(s.d.Cats), p)
		return
	}
	if err != nil {
		s.cloudFail(err, "들어가지")
		return
	}
	conflicts, _ := filepath.Glob(filepath.Join(dir, "data *.json"))
	if c.synced && st.ModTime().Equal(c.seenMod) && st.Size() == c.seenSize && len(conflicts) == 0 {
		c.State, c.Msg = "ok", ""
		return
	}
	b, err := os.ReadFile(p)
	if err != nil {
		s.cloudFail(err, "읽지")
		return
	}
	h := sha256.Sum256(b)
	if c.synced && h == c.lastHash && len(conflicts) == 0 {
		c.seenMod, c.seenSize = st.ModTime(), st.Size()
		c.State, c.Msg, c.Last = "ok", "", time.Now().UnixMilli()
		return
	}
	var remote storeData
	if err := json.Unmarshal(b, &remote); err != nil {
		// 아직 다 내려오지 않았거나 다른 기기가 쓰는 중일 수 있어요. 덮어쓰지 않고 다음에 다시 봐요.
		c.seenMod = time.Time{}
		if c.State != "waiting" {
			log.Printf("iCloud: data.json 을 읽지 못했어요(다음에 다시): %v", err)
		}
		c.State, c.Msg = "waiting", "iCloud 의 할 일 파일을 읽는 중이에요"
		return
	}
	others := []storeData{remote}
	var used []string
	for _, cp := range conflicts {
		var o storeData
		if cb, err := os.ReadFile(cp); err == nil && json.Unmarshal(cb, &o) == nil {
			others = append(others, o)
			used = append(used, cp)
		}
	}

	before := canon(&s.d)
	if !c.synced {
		s.backupAs("before-icloud")
	}
	if s.fresh && !c.synced {
		// 새로 깐 맥: 손대지 않은 처음 안내 할 일은 버리고, 분류도 iCloud 것을 그대로 받아요
		s.dropUntouchedSeed()
		if remote.Cats != nil {
			s.d.Cats, s.d.CatsUpdated = remote.Cats, remote.CatsUpdated
		}
	}
	for _, o := range others {
		s.merge(o)
	}
	s.pruneTombstones()
	if app != nil && s.d.WeekStart != app.Settings().WeekStart {
		app.setWeekStartFromCloud(s.d.WeekStart)
		s.rollover(Today())
	}
	for _, t := range s.d.Tasks {
		s.normalize(t)
	}
	changed := !bytes.Equal(before, canon(&s.d))
	if changed {
		s.rev++
		s.save()
		s.exportWidget()
		log.Printf("iCloud: 다른 기기에서 바뀐 것을 합쳤어요 (할 일 %d개)", len(s.d.Tasks))
	}
	out := canonIndent(&s.d)
	if !bytes.Equal(canon(&s.d), canon(&remote)) || len(used) > 0 {
		if err := s.cloudWrite(out); err != nil {
			s.cloudFail(err, "저장하지")
			return
		}
		for _, cp := range used {
			os.Remove(cp)
		}
	} else {
		c.lastHash = h
		c.seenMod, c.seenSize = st.ModTime(), st.Size()
	}
	c.State, c.Msg, c.synced, c.Last = "ok", "", true, time.Now().UnixMilli()
	s.fresh = false
}

func canonIndent(d *storeData) []byte {
	b, _ := json.MarshalIndent(d, "", " ")
	return b
}

// cloudWrite: iCloud 의 data.json 을 한 번에 바꿔요 (임시 파일 → 이름 바꾸기)
func (s *Store) cloudWrite(b []byte) error {
	c := &s.cloud
	p := filepath.Join(c.Dir, "data.json")
	tmp := filepath.Join(c.Dir, ".data.json.writing")
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, p); err != nil {
		os.Remove(tmp)
		return err
	}
	c.lastHash = sha256.Sum256(b)
	if st, err := os.Stat(p); err == nil {
		c.seenMod, c.seenSize = st.ModTime(), st.Size()
	}
	return nil
}

// cloudPushLocked: 맥에서 바뀐 것을 iCloud 에도 써요 (commit 때).
// 이번 실행에서 아직 맞춘 적이 없거나, iCloud 쪽이 그사이 바뀌었으면 덮어쓰지 않고 먼저 합쳐요.
func (s *Store) cloudPushLocked() {
	c := &s.cloud
	if !c.synced || !cloudOn() {
		return
	}
	p := filepath.Join(c.Dir, "data.json")
	st, err := os.Stat(p)
	if err != nil || !st.ModTime().Equal(c.seenMod) || st.Size() != c.seenSize {
		s.cloudSyncLocked()
		return
	}
	if err := s.cloudWrite(canonIndent(&s.d)); err != nil {
		s.cloudFail(err, "저장하지")
		return
	}
	c.State, c.Msg, c.Last = "ok", "", time.Now().UnixMilli()
}

// merge: 다른 기기의 자료를 합쳐요 (규칙은 파일 맨 위)
func (s *Store) merge(o storeData) {
	if s.d.Deleted == nil {
		s.d.Deleted = map[string]int64{}
	}
	for id, at := range o.Deleted {
		if at > s.d.Deleted[id] {
			s.d.Deleted[id] = at
		}
	}
	if o.Cats != nil && (o.CatsUpdated > s.d.CatsUpdated ||
		(o.CatsUpdated == s.d.CatsUpdated && bytes.Compare(canon(o.Cats), canon(s.d.Cats)) > 0)) {
		s.d.Cats, s.d.CatsUpdated = o.Cats, o.CatsUpdated
	}
	for _, rt := range o.Tasks {
		if rt == nil || rt.ID == "" {
			continue
		}
		lt := s.task(rt.ID)
		if lt == nil {
			if s.d.Deleted[rt.ID] >= rt.Updated {
				continue
			}
			cp := *rt
			s.d.Tasks = append(s.d.Tasks, &cp)
			continue
		}
		if rt.Updated > lt.Updated || (rt.Updated == lt.Updated && bytes.Compare(canon(rt), canon(lt)) > 0) {
			*lt = *rt
		}
	}
	kept := s.d.Tasks[:0]
	for _, t := range s.d.Tasks {
		if at, ok := s.d.Deleted[t.ID]; ok && at >= t.Updated {
			continue
		}
		kept = append(kept, t)
	}
	s.d.Tasks = kept
	if (o.WeekStart == "sun" || o.WeekStart == "mon") && (o.WeekStartAt > s.d.WeekStartAt ||
		(o.WeekStartAt == s.d.WeekStartAt && o.WeekStart > s.d.WeekStart)) {
		s.d.WeekStart, s.d.WeekStartAt = o.WeekStart, o.WeekStartAt
	}
	if o.LastDay > s.d.LastDay {
		s.d.LastDay = o.LastDay
	}
}

func (s *Store) pruneTombstones() {
	limit := time.Now().AddDate(0, 0, -tombstoneDays).UnixMilli()
	for id, at := range s.d.Deleted {
		if at < limit {
			delete(s.d.Deleted, id)
		}
	}
}

func (s *Store) dropUntouchedSeed() {
	kept := s.d.Tasks[:0]
	for _, t := range s.d.Tasks {
		if s.seedIDs[t.ID] && t.Updated == t.Created && !t.Done {
			continue
		}
		kept = append(kept, t)
	}
	s.d.Tasks = kept
}

// backupAs: 지금 맥 안의 자료를 backups/<이름>-<날짜>.json 으로 남겨요 (같은 날 한 번)
func (s *Store) backupAs(name string) {
	dir := filepath.Join(s.dir, "backups")
	dst := filepath.Join(dir, name+"-"+time.Now().Format("2006-01-02")+".json")
	if fileExists(dst) {
		return
	}
	os.MkdirAll(dir, 0o755)
	os.WriteFile(dst, canonIndent(&s.d), 0o644)
}

// CloudStatus: 화면 · 진단에 보여 줄 상태
func (s *Store) cloudStatusLocked() map[string]any {
	c := s.cloud
	st := c.State
	if st == "" {
		st = "starting"
	}
	return map[string]any{"state": st, "msg": c.Msg, "last": c.Last, "moved": c.Moved, "dir": c.Dir}
}

func (s *Store) CloudSummary() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := s.cloud
	last := "-"
	if c.Last > 0 {
		last = time.UnixMilli(c.Last).Format("01-02 15:04:05")
	}
	return c.State + " · 마지막 " + last + " · " + c.Dir + " " + c.Msg
}

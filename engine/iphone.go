package main

// 아이폰 DayROAD 파일을 최신으로 받아 두기 (맥 v1.5.0, 사용자 요청 2026-11-19)
//
// 아이폰 앱은 무료 애플 ID 라서 스스로 업데이트할 수 없고, 7일마다 맥 Xcode 에서 ▶ 로 다시 설치해요.
// 그래서 맥 DayROAD 가 자기 업데이트를 확인할 때(켠 뒤 40초, 그다음 6시간마다) releases/latest-ios.json 도 보고,
// 새 버전이 있으면 사용자의 DayROAD-iPhone 폴더(기본: 문서 › DayROAD-iPhone)를 통째로 새것으로 바꿔 둬요.
// 그러면 다음 ▶ 한 번에 새 버전이 아이폰에 들어가요.
//   - 사용자가 Xcode 에서 고른 팀(DEVELOPMENT_TEAM)과, 바꿨다면 Bundle Identifier 는 새 프로젝트 파일에 옮겨 적어요 (팀을 다시 고를 필요 없음)
//   - Xcode 개인 설정(xcuserdata)도 옮겨요
//   - 예전 폴더는 Support/ios-backup.noindex/ 에 2개까지 남겨요
//   - 맥이 '문서 폴더 접근' 허락을 묻는 동안 멈추지 않게, 폴더 확인은 3초 안에 끝나지 않으면 이번엔 건너뛰어요

import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const iosDefaultBundle = "com.neverthelessd.dayroad.iphone"

type IOSFiles struct {
	mu      sync.Mutex
	support string
	State_  string // off | checking | ok | updated | notfound | asking | error
	Msg     string
	Dir     string
	Local   string // 폴더 안의 버전
	Latest  string // 나와 있는 최신 버전
	Updated int64  // 이번에 바꿔 둔 시각
	Notes   []string
	probing atomic.Bool
	running atomic.Bool
}

func NewIOSFiles(support string) *IOSFiles { return &IOSFiles{support: support, State_: "checking"} }

func (x *IOSFiles) State() map[string]any {
	x.mu.Lock()
	defer x.mu.Unlock()
	return map[string]any{"state": x.State_, "msg": x.Msg, "dir": x.Dir, "local": x.Local, "latest": x.Latest, "updated": x.Updated, "notes": x.Notes}
}

func (x *IOSFiles) set(f func()) {
	x.mu.Lock()
	f()
	x.mu.Unlock()
}

func iosFeedURL() string {
	if u := env("IOS_UPDATE_URL"); u != "" {
		return u
	}
	return feedBase + "latest-ios.json"
}

// iosDir: 사용자가 고른 폴더, 없으면 문서 › DayROAD-iPhone
func iosDir() string {
	if d := app.Settings().IOSFolder; d != "" {
		return d
	}
	if d := env("IOS_DIR"); d != "" { // 시험용
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Documents", "DayROAD-iPhone")
}

func (x *IOSFiles) loop() {
	time.Sleep(40 * time.Second)
	for {
		x.Run()
		time.Sleep(6 * time.Hour)
	}
}

// Run: 한 번 확인하고 필요하면 바꿔요
func (x *IOSFiles) Run() {
	if !x.running.CompareAndSwap(false, true) {
		return
	}
	defer x.running.Store(false)
	if !app.Settings().IOSUpdate {
		x.set(func() { x.State_, x.Msg = "off", "" })
		return
	}
	dir := iosDir()
	x.set(func() { x.Dir = dir })

	// 폴더 확인 (맥이 허락을 물으면 기다리지 않아요)
	if !x.probeDir(dir) {
		x.set(func() {
			x.State_, x.Msg = "asking", "맥이 DayROAD 가 이 폴더를 써도 되는지 묻고 있어요. ‘허용’을 눌러 주세요"
		})
		return
	}
	if !fileExists(filepath.Join(dir, "DayROAD.xcodeproj", "project.pbxproj")) {
		x.set(func() {
			x.State_, x.Msg, x.Local = "notfound", "아이폰용 폴더(DayROAD-iPhone)를 찾지 못했어요", ""
		})
		return
	}
	local := readVersionFile(filepath.Join(dir, "VERSION"))
	x.set(func() { x.Local = local })

	rel, err := fetchRelease(iosFeedURL())
	if err != nil {
		x.set(func() { x.State_, x.Msg = "error", err.Error() })
		return
	}
	x.set(func() { x.Latest, x.Notes = rel.Version, rel.Notes })
	if local != "" && compareVersions(rel.Version, local) <= 0 {
		x.set(func() {
			if x.State_ != "updated" {
				x.State_, x.Msg = "ok", ""
			}
		})
		return
	}
	if err := x.replace(dir, local, rel); err != nil {
		log.Printf("아이폰 파일: 바꾸지 못했어요: %v", err)
		x.set(func() { x.State_, x.Msg = "error", "아이폰용 파일을 바꾸지 못했어요: "+err.Error() })
		return
	}
	log.Printf("아이폰 파일: %s → %s 로 바꿔 뒀어요 (%s)", local, rel.Version, dir)
	x.set(func() { x.State_, x.Msg, x.Local, x.Updated = "updated", "", rel.Version, time.Now().UnixMilli() })
}

func (x *IOSFiles) probeDir(dir string) bool {
	if !x.probing.CompareAndSwap(false, true) {
		return false
	}
	done := make(chan struct{})
	go func() {
		defer x.probing.Store(false)
		defer close(done)
		os.Stat(filepath.Join(dir, "DayROAD.xcodeproj"))
		os.ReadDir(filepath.Dir(dir))
	}()
	select {
	case <-done:
		return true
	case <-time.After(3 * time.Second):
		log.Printf("아이폰 파일: 폴더 확인이 3초 넘게 멈춤 — 맥이 허락을 묻는 중일 수 있어요")
		return false
	}
}

func readVersionFile(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func fetchRelease(url string) (*Release, error) { return fetchFrom(url) }

var (
	reTeam   = regexp.MustCompile(`DEVELOPMENT_TEAM = "?([A-Z0-9]{10})"?;`)
	reBundle = regexp.MustCompile(`PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;`)
)

// carryProjectSettings: 예전 프로젝트 파일에서 고른 팀 · 바꾼 Bundle Identifier 를 새 파일에 옮겨 적어요
func carryProjectSettings(oldPbx, newPbx string) (string, string) {
	team := ""
	if m := reTeam.FindStringSubmatch(oldPbx); m != nil {
		team = m[1]
		newPbx = strings.ReplaceAll(newPbx, `DEVELOPMENT_TEAM = "";`, "DEVELOPMENT_TEAM = "+team+";")
	}
	bundle := ""
	for _, m := range reBundle.FindAllStringSubmatch(oldPbx, -1) {
		if !strings.HasSuffix(m[1], ".widget") {
			bundle = m[1]
			break
		}
	}
	if bundle != "" && bundle != iosDefaultBundle {
		newPbx = strings.ReplaceAll(newPbx, iosDefaultBundle+".widget;", bundle+".widget;")
		newPbx = strings.ReplaceAll(newPbx, iosDefaultBundle+";", bundle+";")
	}
	return newPbx, team
}

func (x *IOSFiles) replace(dir, local string, rel *Release) error {
	work := filepath.Join(x.support, "ios-update")
	os.RemoveAll(work)
	if err := os.MkdirAll(work, 0o755); err != nil {
		return err
	}
	defer os.RemoveAll(work)
	zipPath := filepath.Join(work, "ios.zip")
	if err := download(assetURL2(iosFeedURL(), rel.Zip), zipPath, func(int64, int64) {}); err != nil {
		return err
	}
	if rel.Sha256 != "" && !strings.EqualFold(sha256File(zipPath), rel.Sha256) {
		return errors.New("받은 파일이 손상됐어요 (확인 값이 달라요)")
	}
	out := filepath.Join(work, "x")
	if err := unzipAll(zipPath, out); err != nil {
		return err
	}
	src := filepath.Join(out, "DayROAD-iPhone")
	newPbxPath := filepath.Join(src, "DayROAD.xcodeproj", "project.pbxproj")
	nb, err := os.ReadFile(newPbxPath)
	if err != nil {
		return errors.New("받은 파일 안에 Xcode 프로젝트가 없어요")
	}
	ob, err := os.ReadFile(filepath.Join(dir, "DayROAD.xcodeproj", "project.pbxproj"))
	if err != nil {
		return err
	}
	np, team := carryProjectSettings(string(ob), string(nb))
	if err := os.WriteFile(newPbxPath, []byte(np), 0o644); err != nil {
		return err
	}
	// Xcode 개인 설정(마지막에 고른 기기 등)
	for _, rel := range []string{"DayROAD.xcodeproj/xcuserdata", "DayROAD.xcodeproj/project.xcworkspace/xcuserdata"} {
		if fileExists(filepath.Join(dir, rel)) {
			copyTree(filepath.Join(dir, rel), filepath.Join(src, rel))
		}
	}
	// 예전 폴더 보관 → 새 폴더로
	bk := filepath.Join(x.support, "ios-backup.noindex")
	os.MkdirAll(bk, 0o755)
	name := "DayROAD-iPhone-" + orStr(local, "old") + "-" + time.Now().Format("20060102-150405")
	if err := moveDir(dir, filepath.Join(bk, name)); err != nil {
		return fmt.Errorf("예전 폴더를 옮기지 못했어요: %v", err)
	}
	if err := moveDir(src, dir); err != nil {
		moveDir(filepath.Join(bk, name), dir) // 되돌리기
		return fmt.Errorf("새 폴더를 넣지 못했어요: %v", err)
	}
	pruneBackups(bk, 2)
	log.Printf("아이폰 파일: 팀 %s 옮겨 적음", orStr(team, "(없음 — Xcode 에서 팀을 골라야 해요)"))
	return nil
}

func assetURL2(feed, rel string) string {
	if strings.HasPrefix(rel, "http://") || strings.HasPrefix(rel, "https://") {
		return rel
	}
	base := feed
	if i := strings.Index(base, "?"); i >= 0 {
		base = base[:i]
	}
	return base[:strings.LastIndex(base, "/")+1] + rel
}

func orStr(a, b string) string {
	if a == "" {
		return b
	}
	return a
}

func copyTree(from, to string) {
	filepath.Walk(from, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		r, _ := filepath.Rel(from, p)
		t := filepath.Join(to, r)
		if info.IsDir() {
			os.MkdirAll(t, 0o755)
			return nil
		}
		copyPlain(p, t)
		return nil
	})
}

func pruneBackups(dir string, keep int) {
	es, _ := os.ReadDir(dir)
	var names []string
	for _, e := range es {
		if e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Slice(names, func(i, j int) bool {
		a, _ := os.Stat(filepath.Join(dir, names[i]))
		b, _ := os.Stat(filepath.Join(dir, names[j]))
		return a.ModTime().After(b.ModTime())
	})
	for i, n := range names {
		if i >= keep {
			os.RemoveAll(filepath.Join(dir, n))
		}
	}
}

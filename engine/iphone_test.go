package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const newPbx = `buildSettings = { DEVELOPMENT_TEAM = ""; PRODUCT_BUNDLE_IDENTIFIER = com.neverthelessd.dayroad.iphone; };
buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = com.neverthelessd.dayroad.iphone.widget; };`

// 새 아이폰 파일로 바꿀 때: 고른 팀 · 바꾼 Bundle Identifier · Xcode 개인 설정을 옮기고 예전 폴더는 보관
func TestIOSReplace(t *testing.T) {
	var zb bytes.Buffer
	zw := zip.NewWriter(&zb)
	for name, body := range map[string]string{
		"DayROAD-iPhone/DayROAD.xcodeproj/project.pbxproj": newPbx,
		"DayROAD-iPhone/VERSION":                           "1.0.2\n",
		"DayROAD-iPhone/DayROAD/New.swift":                 "// new",
	} {
		w, _ := zw.Create(name)
		w.Write([]byte(body))
	}
	zw.Close()
	sum := sha256.Sum256(zb.Bytes())
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".zip") {
			w.Write(zb.Bytes())
			return
		}
		w.Write([]byte(`{"version":"1.0.2","zip":"ios.zip","sha256":"` + hex.EncodeToString(sum[:]) + `","notes":["x"]}`))
	}))
	defer srv.Close()
	t.Setenv("DAYROAD_IOS_UPDATE_URL", srv.URL+"/latest-ios.json")

	root := t.TempDir()
	dir := filepath.Join(root, "Documents", "DayROAD-iPhone")
	os.MkdirAll(filepath.Join(dir, "DayROAD.xcodeproj", "xcuserdata", "me.xcuserdatad"), 0o755)
	os.WriteFile(filepath.Join(dir, "DayROAD.xcodeproj", "project.pbxproj"), []byte(`DEVELOPMENT_TEAM = AB12CD34EF; PRODUCT_BUNDLE_IDENTIFIER = com.neverthelessd.dayroad.iphone2;
PRODUCT_BUNDLE_IDENTIFIER = com.neverthelessd.dayroad.iphone2.widget;`), 0o644)
	os.WriteFile(filepath.Join(dir, "DayROAD.xcodeproj", "xcuserdata", "me.xcuserdatad", "x.plist"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "VERSION"), []byte("1.0.1\n"), 0o644)

	rel, err := fetchRelease(iosFeedURL())
	if err != nil || rel.Version != "1.0.2" {
		t.Fatalf("feed: %v %+v", err, rel)
	}
	x := NewIOSFiles(filepath.Join(root, "support"))
	if err := x.replace(dir, "1.0.1", rel); err != nil {
		t.Fatal(err)
	}
	pb, _ := os.ReadFile(filepath.Join(dir, "DayROAD.xcodeproj", "project.pbxproj"))
	p := string(pb)
	if !strings.Contains(p, "DEVELOPMENT_TEAM = AB12CD34EF;") {
		t.Fatalf("팀이 안 옮겨졌어요:\n%s", p)
	}
	if !strings.Contains(p, "= com.neverthelessd.dayroad.iphone2;") || !strings.Contains(p, "= com.neverthelessd.dayroad.iphone2.widget;") {
		t.Fatalf("Bundle Identifier 가 안 옮겨졌어요:\n%s", p)
	}
	if readVersionFile(filepath.Join(dir, "VERSION")) != "1.0.2" || !fileExists(filepath.Join(dir, "DayROAD", "New.swift")) {
		t.Fatal("새 파일이 안 들어갔어요")
	}
	if !fileExists(filepath.Join(dir, "DayROAD.xcodeproj", "xcuserdata", "me.xcuserdatad", "x.plist")) {
		t.Fatal("Xcode 개인 설정이 안 옮겨졌어요")
	}
	if m, _ := filepath.Glob(filepath.Join(root, "support", "ios-backup.noindex", "DayROAD-iPhone-1.0.1-*")); len(m) != 1 {
		t.Fatal("예전 폴더 보관이 없어요")
	}
	// 팀을 안 골랐던 경우엔 그대로 비어 있어요
	np, team := carryProjectSettings(`DEVELOPMENT_TEAM = "";`, newPbx)
	if team != "" || !strings.Contains(np, `DEVELOPMENT_TEAM = "";`) || !strings.Contains(np, "dayroad.iphone;") {
		t.Fatal("팀 없음 처리")
	}
}

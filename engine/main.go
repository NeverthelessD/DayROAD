// DayROAD — 오늘 · 이번 주 할 일 (macOS, Apple Silicon)
// made by. Nevertheless_D
package main

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"
)

// build is the app version, set with -ldflags "-X main.build=1.2.3".
var build = "0.0.0-dev"

//go:embed web
var webFiles embed.FS

type MorningSetting struct {
	On   bool   `json:"on"`
	Time string `json:"time"`
}

type DueSetting struct {
	On   bool   `json:"on"`
	Days int    `json:"days"`
	Time string `json:"time"`
}

type Settings struct {
	Appearance    string         `json:"appearance"` // system | light | dark
	AutoUpdate    bool           `json:"autoUpdate"`
	WeekStart     string         `json:"weekStart"` // mon | sun
	CarryOver     bool           `json:"carryOver"`
	Morning       MorningSetting `json:"morning"`
	DueRemind     DueSetting     `json:"dueRemind"`
	CalendarShow  bool           `json:"calendarShow"`
	HiddenCals    []string       `json:"hiddenCals"`
	EventCalendar string         `json:"eventCalendar"`
	RemindersSync bool           `json:"remindersSync"`
	RemindersList string         `json:"remindersList"`
	UI            map[string]any `json:"ui"`
}

type App struct {
	support string
	token   string
	port    int

	mu       sync.Mutex
	settings Settings

	store *Store
	upd   *Updater
}

var app *App

var started = time.Now()

func env(k string) string { return os.Getenv("DAYROAD_" + k) }

func main() {
	log.SetFlags(log.LstdFlags)
	home, _ := os.UserHomeDir()
	support := env("SUPPORT")
	if support == "" {
		if runtime.GOOS == "darwin" {
			support = filepath.Join(home, "Library", "Application Support", "DayROAD")
		} else {
			support = filepath.Join(home, ".dayroad")
		}
	}
	if env("SUPERVISOR") == "1" {
		os.MkdirAll(support, 0o755)
		runSupervisor(support)
		return
	}
	token := env("TOKEN")
	if token == "" {
		token = randID(16)
	}
	app = &App{support: support, token: token}
	os.MkdirAll(support, 0o755)
	os.Rename(filepath.Join(support, "engine.log"), filepath.Join(support, "engine.prev.log"))
	if f, err := os.OpenFile(filepath.Join(support, "engine.log"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644); err == nil {
		log.SetOutput(io.MultiWriter(os.Stderr, f))
	}
	app.loadSettings()
	app.store = NewStore(support)
	app.upd = NewUpdater(support)
	app.store.Tick() // 날짜가 바뀌었으면 못 끝낸 일 넘기기 · 반복 정리 → 위젯 파일 쓰기

	go heartbeat(support)
	ln := listen(env("PORT"), env("PORT_WAIT") == "1")
	app.port = ln.Addr().(*net.TCPAddr).Port
	writeFileAtomic(filepath.Join(support, "token"), []byte(token), 0o600)
	writeFileAtomic(filepath.Join(support, "port"), []byte(strconv.Itoa(app.port)), 0o644)
	writeFileAtomic(filepath.Join(support, "lastport"), []byte(strconv.Itoa(app.port)), 0o644)
	log.Printf("DayROAD %s listening on %d (pid %d, 지킴이 %v)", build, app.port, os.Getpid(), env("CHILD") == "1")

	if app.port != defaultPort {
		go func() {
			defer recoverLog("diag listener")
			if ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", defaultPort)); err == nil {
				m := http.NewServeMux()
				m.HandleFunc("/diag", app.handleDiag)
				http.Serve(ln, hostGuard(m))
			}
		}()
	}
	go app.watchParent()
	go func() { defer recoverLog("autoLoop"); app.upd.autoLoop() }()
	go func() { defer recoverLog("store loop"); app.store.loop() }()
	srv := &http.Server{Handler: hostGuard(recordRequests(app.routes())), ErrorLog: log.Default()}
	log.Fatal(srv.Serve(ln))
}

// defaultPort: 항상 같은 주소를 쓰면 엔진이 다시 켜져도 열려 있던 창이 이어지고, 진단 페이지도 찾기 쉬워요.
const defaultPort = 47951

func listen(pref string, wait bool) net.Listener {
	p, err := strconv.Atoi(pref)
	if err != nil || p <= 0 {
		p = defaultPort
	}
	tries := 1
	if wait {
		tries = 20
	}
	for i := 0; i < tries; i++ {
		if ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", p)); err == nil {
			return ln
		}
		time.Sleep(150 * time.Millisecond)
	}
	if p != defaultPort {
		if ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", defaultPort)); err == nil {
			return ln
		}
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatal(err)
	}
	return ln
}

// ---------------------------------------------------------------- lifecycle

func nativeShell() bool { return env("SHELL") == "native" }

// watchParent: 지킴이(부모)가 사라지면 엔진도 끝나요 — 혼자 남아 몰래 돌지 않게
func (a *App) watchParent() {
	if env("CHILD") != "1" {
		return
	}
	ppid := os.Getppid()
	for range time.Tick(2 * time.Second) {
		if os.Getppid() != ppid {
			a.shutdownWhy("지킴이가 사라짐")
		}
	}
}

func (a *App) shutdownWhy(why string) {
	log.Printf("shutdown: %s", why)
	a.store.Flush()
	markCleanExit(a.support, why)
	if b, err := os.ReadFile(filepath.Join(a.support, "port")); err == nil && string(b) == strconv.Itoa(a.port) {
		os.Remove(filepath.Join(a.support, "port"))
	}
	os.Exit(0)
}

// ---------------------------------------------------------------- settings

func (a *App) settingsPath() string { return filepath.Join(a.support, "settings.json") }

func defaultSettings() Settings {
	return Settings{
		Appearance: "system", AutoUpdate: true, WeekStart: "mon", CarryOver: true,
		Morning:      MorningSetting{On: false, Time: "08:30"},
		DueRemind:    DueSetting{On: true, Days: 1, Time: "09:00"},
		CalendarShow: true,
		UI:           map[string]any{},
	}
}

var hhmm = regexp.MustCompile(`^([01]\d|2[0-3]):[0-5]\d$`)

func (s *Settings) normalize() {
	d := defaultSettings()
	switch s.Appearance {
	case "system", "light", "dark":
	default:
		s.Appearance = d.Appearance
	}
	if s.WeekStart != "mon" && s.WeekStart != "sun" {
		s.WeekStart = d.WeekStart
	}
	if !hhmm.MatchString(s.Morning.Time) {
		s.Morning.Time = d.Morning.Time
	}
	if !hhmm.MatchString(s.DueRemind.Time) {
		s.DueRemind.Time = d.DueRemind.Time
	}
	if s.DueRemind.Days < 0 || s.DueRemind.Days > 7 {
		s.DueRemind.Days = d.DueRemind.Days
	}
	if s.UI == nil {
		s.UI = map[string]any{}
	}
	if s.HiddenCals == nil {
		s.HiddenCals = []string{}
	}
}

func (a *App) loadSettings() {
	a.settings = defaultSettings()
	if b, err := os.ReadFile(a.settingsPath()); err == nil {
		_ = json.Unmarshal(b, &a.settings)
	}
	a.settings.normalize()
}

func (a *App) saveSettings() {
	b, _ := json.MarshalIndent(a.settings, "", "  ")
	writeFileAtomic(a.settingsPath(), b, 0o644)
}

func (a *App) Settings() Settings {
	a.mu.Lock()
	defer a.mu.Unlock()
	s := a.settings
	s.UI = make(map[string]any, len(a.settings.UI))
	for k, v := range a.settings.UI {
		s.UI[k] = v
	}
	s.HiddenCals = append([]string{}, a.settings.HiddenCals...)
	return s
}

func (a *App) settingsJSON() map[string]any {
	s := a.Settings()
	b, _ := json.Marshal(s)
	out := map[string]any{}
	json.Unmarshal(b, &out)
	out["build"] = build
	out["platform"] = runtime.GOOS + "/" + runtime.GOARCH
	return out
}

func (a *App) handleSettings(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		var in map[string]json.RawMessage
		if err := readJSON(r, &in); err != nil {
			jsonError(w, 400, "bad request")
			return
		}
		a.mu.Lock()
		cur, _ := json.Marshal(a.settings)
		m := map[string]json.RawMessage{}
		json.Unmarshal(cur, &m)
		for k, v := range in {
			if k == "ui" {
				var ui map[string]any
				if json.Unmarshal(v, &ui) == nil {
					for kk, vv := range ui {
						a.settings.UI[kk] = vv
					}
				}
				continue
			}
			if _, ok := m[k]; ok {
				m[k] = v
			}
		}
		b, _ := json.Marshal(m)
		next := a.settings
		if json.Unmarshal(b, &next) == nil {
			next.UI = a.settings.UI
			next.normalize()
			a.settings = next
		}
		a.saveSettings()
		a.mu.Unlock()
		a.store.Tick() // 주 시작 요일 · 넘기기 설정이 바뀌었을 수 있어요
	}
	writeJSON(w, a.settingsJSON())
}

// ---------------------------------------------------------------- routes

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	sub, _ := fs.Sub(webFiles, "web")
	static := http.FileServer(http.FS(sub))

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || r.URL.Path == "/index.html" {
			if r.URL.Query().Get("t") != a.token {
				w.Header().Set("Content-Type", "text/html; charset=utf-8")
				w.WriteHeader(http.StatusForbidden)
				io.WriteString(w, "<meta charset=utf-8><body style='font:15px -apple-system;padding:40px'>DayROAD 앱을 다시 실행해 주세요.</body>")
				return
			}
			b, _ := webFiles.ReadFile("web/index.html")
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-store")
			w.Write(b)
			return
		}
		if strings.HasSuffix(r.URL.Path, ".js") || strings.HasSuffix(r.URL.Path, ".css") {
			w.Header().Set("Cache-Control", "no-cache")
		} else if strings.HasPrefix(r.URL.Path, "/fonts/") {
			w.Header().Set("Cache-Control", "public, max-age=604800")
		}
		static.ServeHTTP(w, r)
	})

	mux.HandleFunc("/diag", a.handleDiag)

	api := func(path string, h http.HandlerFunc) {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			t := r.Header.Get("x-token")
			if t == "" {
				t = r.URL.Query().Get("t")
			}
			if t != a.token {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			defer func() {
				if v := recover(); v != nil {
					log.Printf("PANIC in %s: %v\n%s", path, v, debug.Stack())
					jsonError(w, 500, "앱 안에서 문제가 생겼어요. 다시 시도해 주세요")
				}
			}()
			h(w, r)
		})
	}

	api("/api/ping", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"ok": true, "build": build, "shell": env("SHELL")})
	})
	api("/api/quit", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"ok": true})
		go func() { time.Sleep(300 * time.Millisecond); a.shutdownWhy("종료 버튼") }()
	})
	api("/api/clientlog", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Items []string `json:"items"`
		}
		readJSON(r, &in)
		for i, x := range in.Items {
			if i >= 30 {
				break
			}
			if len(x) > 600 {
				x = x[:600]
			}
			diag.clientErr(x)
			log.Printf("client: %s", x)
		}
		writeJSON(w, map[string]any{"ok": true})
	})
	api("/api/poll", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"build": build, "update": a.upd.State(), "shell": env("SHELL"), "rev": a.store.Rev(), "today": a.store.Today()})
	})
	api("/api/settings", a.handleSettings)

	// 할 일 · 분류
	a.storeRoutes(api)

	api("/api/update/check", func(w http.ResponseWriter, r *http.Request) {
		a.upd.Check(true)
		writeJSON(w, a.upd.State())
	})
	api("/api/update/install", func(w http.ResponseWriter, r *http.Request) {
		go func() { defer recoverLog("install"); a.upd.Install() }()
		writeJSON(w, map[string]any{"ok": true})
	})
	api("/api/update/rollback", func(w http.ResponseWriter, r *http.Request) {
		if err := a.upd.Rollback(); err != nil {
			jsonError(w, 500, err.Error())
			return
		}
		writeJSON(w, map[string]any{"ok": true})
	})
	api("/api/update/restart", func(w http.ResponseWriter, r *http.Request) {
		if err := a.upd.Restart(a.port, a.token); err != nil {
			jsonError(w, 500, err.Error())
			return
		}
		writeJSON(w, map[string]any{"ok": true})
	})
	return mux
}

// Only answer requests addressed to 127.0.0.1 / localhost (DNS rebinding protection).
func hostGuard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if h, _, err := net.SplitHostPort(host); err == nil {
			host = h
		}
		if host != "127.0.0.1" && host != "localhost" {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------- utils

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(w).Encode(v)
}

func jsonError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]any{"ok": false, "error": msg})
}

func readJSON(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(io.LimitReader(r.Body, 4<<20)).Decode(v)
}

func randID(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func writeFileAtomic(path string, b []byte, perm os.FileMode) {
	tmp := path + ".tmp"
	if os.WriteFile(tmp, b, perm) == nil {
		os.Rename(tmp, path)
	}
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

func lastLine(s string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	return strings.TrimSpace(lines[len(lines)-1])
}

func init() {
	mime.AddExtensionType(".js", "text/javascript")
	mime.AddExtensionType(".woff2", "font/woff2")
}

func recoverLog(where string) {
	if v := recover(); v != nil {
		log.Printf("PANIC in %s: %v\n%s", where, v, debug.Stack())
	}
}

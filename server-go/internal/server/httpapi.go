package server

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
)

// tokenIssuer is the subset of Server used by HTTPServer to issue tokens.
type tokenIssuer interface {
	IssueToken(accountID int64, username string) string
}

// HTTPServer runs the plain-HTTP management / registration API on port 6970.
type HTTPServer struct {
	db     *db.DB
	world  interface{ PlayerCount() int32 }
	tokens tokenIssuer
	log    *slog.Logger
	addr   string
}

// NewHTTPServer creates the HTTP API server.
// Pass the game Server as `tokens` so the HTTP token endpoint can issue launcher tokens.
func NewHTTPServer(addr string, database *db.DB, w interface{ PlayerCount() int32 }, tokens tokenIssuer, log *slog.Logger) *HTTPServer {
	return &HTTPServer{db: database, world: w, tokens: tokens, log: log, addr: addr}
}

// ListenAndServe starts the HTTP listener. Blocks until ctx is cancelled.
func (h *HTTPServer) ListenAndServe(ctx context.Context) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/status", h.handleStatus)
	mux.HandleFunc("/api/register", h.handleRegister)
	mux.HandleFunc("/api/login", h.handleLogin)
	mux.HandleFunc("/api/auth/token", h.handleAuthToken)

	srv := &http.Server{
		Addr:         h.addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutCtx)
	}()

	h.log.Info("HTTP API listening", "addr", h.addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func (h *HTTPServer) handleStatus(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	w.Header().Set("Content-Type", "application/json")
	count := h.world.PlayerCount()
	fmt.Fprintf(w, `{"online":%d,"status":"ok"}`, count)
}

func (h *HTTPServer) handleRegister(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := readJSON(r.Body, &body); err != nil {
		jsonError(w, "Invalid request body.", http.StatusBadRequest)
		return
	}

	if err := validateUsername(body.Username); err != nil {
		jsonError(w, err.Error(), http.StatusBadRequest)
		return
	}
	if len(body.Password) < 6 {
		jsonError(w, "Password must be at least 6 characters.", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	if err := h.db.CreateAccount(ctx, body.Username, body.Password); err != nil {
		switch err {
		case db.ErrUsernameTaken:
			jsonError(w, "Username already taken.", http.StatusConflict)
		default:
			h.log.Error("register HTTP error", "err", err)
			jsonError(w, "Internal error.", http.StatusInternalServerError)
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"ok":true}`)
}

func (h *HTTPServer) handleLogin(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := readJSON(r.Body, &body); err != nil {
		jsonError(w, "Invalid request body.", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	account, err := h.db.VerifyAccount(ctx, body.Username, body.Password)
	if err != nil {
		switch err {
		case db.ErrInvalidCredentials:
			jsonError(w, "Invalid credentials.", http.StatusUnauthorized)
		case db.ErrAccountBanned:
			jsonError(w, "Account is banned.", http.StatusForbidden)
		default:
			jsonError(w, "Internal error.", http.StatusInternalServerError)
		}
		return
	}

	chars, err := h.db.ListChars(ctx, account.ID)
	if err != nil {
		h.log.Error("login: list chars error", "err", err)
		chars = nil
	}

	type charJSON struct {
		Name    string `json:"name"`
		Level   int    `json:"level"`
		ClassID int    `json:"class_id"`
	}
	charList := make([]charJSON, len(chars))
	for i, c := range chars {
		charList[i] = charJSON{Name: c.Name, Level: c.Level, ClassID: c.ClassID}
	}

	resp := map[string]any{
		"ok":         true,
		"username":   account.Username,
		"characters": charList,
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *HTTPServer) handleAuthToken(w http.ResponseWriter, r *http.Request) {
	setCORS(w)
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := readJSON(r.Body, &body); err != nil {
		jsonError(w, "Invalid request body.", http.StatusBadRequest)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	account, err := h.db.VerifyAccount(ctx, body.Username, body.Password)
	if err != nil {
		switch err {
		case db.ErrInvalidCredentials:
			jsonError(w, "Invalid credentials.", http.StatusUnauthorized)
		case db.ErrAccountBanned:
			jsonError(w, "Account is banned.", http.StatusForbidden)
		default:
			h.log.Error("auth/token HTTP error", "err", err)
			jsonError(w, "Internal error.", http.StatusInternalServerError)
		}
		return
	}

	token := h.tokens.IssueToken(account.ID, account.Username)

	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"ok":true,"token":%q,"expires_in":300}`, token)
}

func setCORS(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
}

func readJSON(r io.ReadCloser, v any) error {
	defer r.Close()
	return json.NewDecoder(io.LimitReader(r, 64*1024)).Decode(v)
}

func jsonError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	b, _ := json.Marshal(map[string]any{"ok": false, "error": msg})
	_, _ = w.Write(b)
}


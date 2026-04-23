// admin — microservizio di amministrazione Invisible
// Gestisce: whitelist utenti, log errori app, dashboard web
// Protetto da ADMIN_TOKEN — solo l'amministratore ha accesso
package main

import (
	"crypto/ed25519"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// ── Config ────────────────────────────────────────────────────────────────────

type Config struct {
	Port           string
	AdminToken     string
	PostgresHost   string
	PostgresUser   string
	PostgresPass   string
	PostgresDB     string
}

func loadConfig() Config {
	return Config{
		Port:         getEnv("PORT", "8084"),
		AdminToken:   mustEnv("ADMIN_TOKEN"),
		PostgresHost: getEnv("POSTGRES_HOST", "postgres"),
		PostgresUser: getEnv("POSTGRES_USER", "invisible"),
		PostgresPass: mustEnv("POSTGRES_PASSWORD"),
		PostgresDB:   getEnv("POSTGRES_DB", "invisible"),
	}
}

func getEnv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("[ADMIN] variabile d'ambiente obbligatoria mancante: %s", k)
	}
	return v
}

// ── Database ──────────────────────────────────────────────────────────────────

func connectDB(cfg Config) *sql.DB {
	dsn := fmt.Sprintf("host=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.PostgresHost, cfg.PostgresUser, cfg.PostgresPass, cfg.PostgresDB)
	var db *sql.DB
	var err error
	for i := 0; i < 10; i++ {
		db, err = sql.Open("postgres", dsn)
		if err == nil {
			if err = db.Ping(); err == nil {
				break
			}
		}
		log.Printf("[ADMIN] DB non pronto, riprovo (%d/10)...", i+1)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		log.Fatalf("[ADMIN] impossibile connettersi a PostgreSQL: %v", err)
	}
	return db
}

func migrate(db *sql.DB) {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS whitelist (
			identity_hash    TEXT PRIMARY KEY,
			name             TEXT NOT NULL,
			enabled          BOOLEAN DEFAULT true,
			notes            TEXT,
			gdpr_accepted    BOOLEAN DEFAULT false,
			gdpr_accepted_at TIMESTAMP,
			created_at       TIMESTAMP DEFAULT NOW(),
			enabled_at       TIMESTAMP,
			last_seen_at     TIMESTAMP
		);
		CREATE TABLE IF NOT EXISTS error_logs (
			id              SERIAL PRIMARY KEY,
			identity_hash   TEXT,
			app_version     TEXT,
			os_type         TEXT,
			os_version      TEXT,
			device_model    TEXT,
			error_type      TEXT,
			error_message   TEXT,
			stack_trace     TEXT,
			created_at      TIMESTAMP DEFAULT NOW()
		);
	`)
	if err != nil {
		log.Fatalf("[ADMIN] migrazione fallita: %v", err)
	}
	// Aggiungi colonna se non esiste (upgrade da versioni precedenti)
	db.Exec(`ALTER TABLE whitelist ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP`)
	log.Println("[ADMIN] Tabelle DB pronte")
}

// ── Middleware auth ───────────────────────────────────────────────────────────

func (s *Server) requireToken(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-Admin-Token")
		if token == "" {
			token = r.URL.Query().Get("token")
		}
		if token != s.cfg.AdminToken {
			http.Error(w, "non autorizzato", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// ── Server ────────────────────────────────────────────────────────────────────

type Server struct {
	cfg Config
	db  *sql.DB
}

// ── Whitelist API ─────────────────────────────────────────────────────────────

// GET /admin/api/users
func (s *Server) handleListUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`
		SELECT identity_hash, name, enabled, notes, gdpr_accepted, gdpr_accepted_at, created_at, enabled_at, last_seen_at
		FROM whitelist ORDER BY created_at DESC
	`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	type User struct {
		Hash         string  `json:"identity_hash"`
		Name         string  `json:"name"`
		Enabled      bool    `json:"enabled"`
		Notes        *string `json:"notes"`
		GdprAccepted bool    `json:"gdpr_accepted"`
		GdprAt       *string `json:"gdpr_accepted_at"`
		CreatedAt    string  `json:"created_at"`
		EnabledAt    *string `json:"enabled_at"`
		LastSeenAt   *string `json:"last_seen_at"`
		ExpiresAt    *string `json:"expires_at"`
		Online       bool    `json:"online"`
	}

	var users []User
	for rows.Next() {
		var u User
		var gdprAt, enabledAt, lastSeenAt sql.NullTime
		var createdAt time.Time
		if err := rows.Scan(&u.Hash, &u.Name, &u.Enabled, &u.Notes,
			&u.GdprAccepted, &gdprAt, &createdAt, &enabledAt, &lastSeenAt); err != nil {
			continue
		}
		u.CreatedAt = createdAt.Format("2006-01-02 15:04")
		if gdprAt.Valid {
			s := gdprAt.Time.Format("2006-01-02 15:04")
			u.GdprAt = &s
		}
		if enabledAt.Valid {
			s := enabledAt.Time.Format("2006-01-02 15:04")
			u.EnabledAt = &s
			exp := enabledAt.Time.AddDate(1, 0, 0).Format("2006-01-02")
			u.ExpiresAt = &exp
		}
		if lastSeenAt.Valid {
			s := lastSeenAt.Time.Format("2006-01-02 15:04")
			u.LastSeenAt = &s
			u.Online = time.Since(lastSeenAt.Time) < 5*time.Minute
		}
		users = append(users, u)
	}
	if users == nil {
		users = []User{}
	}
	jsonResp(w, users)
}

// POST /admin/api/users  {"identity_hash":"...","name":"...","notes":"..."}
func (s *Server) handleAddUser(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Hash  string `json:"identity_hash"`
		Name  string `json:"name"`
		Notes string `json:"notes"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Hash == "" || req.Name == "" {
		http.Error(w, "dati mancanti", http.StatusBadRequest)
		return
	}
	req.Hash = strings.TrimSpace(req.Hash)
	_, err := s.db.Exec(`
		INSERT INTO whitelist (identity_hash, name, notes, enabled, enabled_at)
		VALUES ($1, $2, $3, true, NOW())
		ON CONFLICT (identity_hash) DO UPDATE SET name=$2, notes=$3, enabled=true, enabled_at=NOW()
	`, req.Hash, req.Name, nullableString(req.Notes))
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	log.Printf("[ADMIN] Utente aggiunto: %s (%s)", req.Name, req.Hash[:8])
	jsonResp(w, map[string]bool{"ok": true})
}

// POST /admin/api/users/toggle?hash=...
func (s *Server) handleToggleUser(w http.ResponseWriter, r *http.Request) {
	hash := r.URL.Query().Get("hash")
	if hash == "" {
		http.Error(w, "hash mancante", http.StatusBadRequest)
		return
	}
	var enabled bool
	err := s.db.QueryRow(`
		UPDATE whitelist SET enabled = NOT enabled,
		enabled_at = CASE WHEN NOT enabled THEN NOW() ELSE enabled_at END
		WHERE identity_hash=$1 RETURNING enabled
	`, hash).Scan(&enabled)
	if err == sql.ErrNoRows {
		http.Error(w, "utente non trovato", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	jsonResp(w, map[string]bool{"enabled": enabled})
}

// DELETE /admin/api/users/delete?hash=...
func (s *Server) handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	hash := r.URL.Query().Get("hash")
	if hash == "" {
		http.Error(w, "hash mancante", http.StatusBadRequest)
		return
	}
	s.db.Exec(`DELETE FROM whitelist WHERE identity_hash=$1`, hash)
	jsonResp(w, map[string]bool{"ok": true})
}

// ── Internal whitelist check (usato da relay/mesh/signaling) ─────────────────

// GET /internal/whitelist/{hash}  → 200 OK | 403 Forbidden
func (s *Server) handleCheckWhitelist(w http.ResponseWriter, r *http.Request) {
	hash := strings.TrimPrefix(r.URL.Path, "/internal/whitelist/")
	if hash == "" {
		http.Error(w, "hash mancante", http.StatusBadRequest)
		return
	}
	var enabled bool
	err := s.db.QueryRow(`SELECT enabled FROM whitelist WHERE identity_hash=$1`, hash).Scan(&enabled)
	if err == sql.ErrNoRows || !enabled {
		http.Error(w, "non autorizzato", http.StatusForbidden)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// ── Error logs ────────────────────────────────────────────────────────────────

// POST /v1/errors  (pubblico, dall'app)
func (s *Server) handleReceiveError(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IdentityHash string `json:"identity_hash"`
		AppVersion   string `json:"app_version"`
		OsType       string `json:"os_type"`
		OsVersion    string `json:"os_version"`
		DeviceModel  string `json:"device_model"`
		ErrorType    string `json:"error_type"`
		ErrorMessage string `json:"error_message"`
		StackTrace   string `json:"stack_trace"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	s.db.Exec(`
		INSERT INTO error_logs (identity_hash,app_version,os_type,os_version,device_model,error_type,error_message,stack_trace)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
	`, nullableString(req.IdentityHash), req.AppVersion, req.OsType, req.OsVersion,
		req.DeviceModel, req.ErrorType, req.ErrorMessage, nullableString(req.StackTrace))
	w.WriteHeader(http.StatusOK)
}

// GET /admin/api/errors
func (s *Server) handleListErrors(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(`
		SELECT id, identity_hash, app_version, os_type, os_version, device_model,
		       error_type, error_message, stack_trace, created_at
		FROM error_logs ORDER BY created_at DESC LIMIT 200
	`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	type ErrLog struct {
		ID           int     `json:"id"`
		IdentityHash *string `json:"identity_hash"`
		AppVersion   string  `json:"app_version"`
		OsType       string  `json:"os_type"`
		OsVersion    string  `json:"os_version"`
		DeviceModel  string  `json:"device_model"`
		ErrorType    string  `json:"error_type"`
		ErrorMessage string  `json:"error_message"`
		StackTrace   *string `json:"stack_trace"`
		CreatedAt    string  `json:"created_at"`
	}

	var logs []ErrLog
	for rows.Next() {
		var l ErrLog
		var createdAt time.Time
		if err := rows.Scan(&l.ID, &l.IdentityHash, &l.AppVersion, &l.OsType, &l.OsVersion,
			&l.DeviceModel, &l.ErrorType, &l.ErrorMessage, &l.StackTrace, &createdAt); err != nil {
			continue
		}
		l.CreatedAt = createdAt.Format("2006-01-02 15:04")
		logs = append(logs, l)
	}
	if logs == nil {
		logs = []ErrLog{}
	}
	jsonResp(w, logs)
}

// DELETE /admin/api/errors — cancella tutti i log errori
func (s *Server) handleClearErrors(w http.ResponseWriter, r *http.Request) {
	res, err := s.db.Exec(`DELETE FROM error_logs`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	n, _ := res.RowsAffected()
	log.Printf("[ADMIN] Cancellati %d log errori", n)
	jsonResp(w, map[string]any{"ok": true, "deleted": n})
}

// DELETE /v1/account — auto-cancellazione account dall'app (firmata con identity key)
// Body: {"identity_key":"...","signature":"..."}
// La firma è su "invisible_delete_account" per prevenire replay
func (s *Server) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		IdentityKey string `json:"identity_key"`
		Signature   string `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityKey == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	pubBytes, err := base64.StdEncoding.DecodeString(req.IdentityKey)
	if err != nil || len(pubBytes) != ed25519.PublicKeySize {
		http.Error(w, "invalid identity key", http.StatusBadRequest)
		return
	}
	sigBytes, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil {
		http.Error(w, "invalid signature", http.StatusBadRequest)
		return
	}
	if !ed25519.Verify(pubBytes, []byte("invisible_delete_account"), sigBytes) {
		http.Error(w, "firma non valida", http.StatusUnauthorized)
		return
	}
	hash := shortHash(req.IdentityKey)
	s.db.Exec(`DELETE FROM whitelist WHERE identity_hash=$1`, hash)
	s.db.Exec(`DELETE FROM error_logs WHERE identity_hash=$1`, hash)
	log.Printf("[ADMIN] Account eliminato su richiesta utente: %s", hash[:8])
	w.WriteHeader(http.StatusOK)
}

// ── ToS / GDPR acceptance (pubblico, dall'app) ───────────────────────────────

// POST /v1/tos/accept
func (s *Server) handleTosAccept(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IdentityKey string `json:"identity_key"`
		TosVersion  string `json:"tos_version"`
		Username    string `json:"username"`
		Signature   string `json:"signature"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IdentityKey == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	// Verifica firma Ed25519
	pubBytes, err := base64.StdEncoding.DecodeString(req.IdentityKey)
	if err != nil || len(pubBytes) != ed25519.PublicKeySize {
		http.Error(w, "invalid identity key", http.StatusBadRequest)
		return
	}
	sigBytes, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil {
		http.Error(w, "invalid signature", http.StatusBadRequest)
		return
	}
	payload := "invisible_tos_v" + req.TosVersion + "_accepted"
	if !ed25519.Verify(pubBytes, []byte(payload), sigBytes) {
		http.Error(w, "firma non valida", http.StatusUnauthorized)
		return
	}
	hash := shortHash(req.IdentityKey)
	name := strings.TrimSpace(req.Username)
	if name == "" {
		name = hash[:8]
	}
	// UPSERT: crea la riga con username e gdpr_accepted=true, enabled=false.
	// L'admin dovrà solo cliccare "Attiva" — nessuna copia hash manuale.
	s.db.Exec(`
		INSERT INTO whitelist (identity_hash, name, gdpr_accepted, gdpr_accepted_at, enabled)
		VALUES ($1, $2, true, NOW(), false)
		ON CONFLICT (identity_hash) DO UPDATE SET gdpr_accepted=true, gdpr_accepted_at=NOW(),
		  name = CASE WHEN whitelist.name='' OR whitelist.name=whitelist.identity_hash THEN $2 ELSE whitelist.name END
	`, hash, name)
	log.Printf("[ADMIN] GDPR accettato: %s", hash[:8])
	w.WriteHeader(http.StatusOK)
}

func shortHash(key string) string {
	if len(key) > 32 {
		return key[len(key)-32:]
	}
	return key
}

// ── Presence update (dal relay quando l'utente si connette) ──────────────────

// POST /internal/presence/{hash} — utente connesso
// DELETE /internal/presence/{hash} — utente disconnesso
func (s *Server) handlePresence(w http.ResponseWriter, r *http.Request) {
	hash := strings.TrimPrefix(r.URL.Path, "/internal/presence/")
	if hash == "" {
		http.Error(w, "hash mancante", http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodPost:
		s.db.Exec(`UPDATE whitelist SET last_seen_at=NOW() WHERE identity_hash=$1`, hash)
	case http.MethodDelete:
		s.db.Exec(`UPDATE whitelist SET last_seen_at=NULL WHERE identity_hash=$1`, hash)
	}
	w.WriteHeader(http.StatusOK)
}

// ── GDPR update (dal legal service quando accettato) ─────────────────────────

// POST /internal/gdpr  {"identity_hash":"..."}
func (s *Server) handleGdprAccepted(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Hash string `json:"identity_hash"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Hash == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	s.db.Exec(`
		UPDATE whitelist SET gdpr_accepted=true, gdpr_accepted_at=NOW()
		WHERE identity_hash=$1
	`, req.Hash)
	w.WriteHeader(http.StatusOK)
}

// ── Dashboard HTML ────────────────────────────────────────────────────────────

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(dashboardHTML))
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func jsonResp(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func nullableString(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	cfg := loadConfig()
	db := connectDB(cfg)
	migrate(db)

	srv := &Server{cfg: cfg, db: db}
	mux := http.NewServeMux()

	// Dashboard — HTML sempre servito, il token è richiesto dal JS per le chiamate API
	mux.HandleFunc("/admin/", srv.handleDashboard)

	// API admin (protette)
	mux.HandleFunc("/admin/api/users", srv.requireToken(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			srv.handleListUsers(w, r)
		case http.MethodPost:
			srv.handleAddUser(w, r)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	mux.HandleFunc("/admin/api/users/toggle", srv.requireToken(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			srv.handleToggleUser(w, r)
		} else {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	mux.HandleFunc("/admin/api/users/delete", srv.requireToken(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodDelete {
			srv.handleDeleteUser(w, r)
		} else {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	mux.HandleFunc("/admin/api/errors", srv.requireToken(func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet:
			srv.handleListErrors(w, r)
		case http.MethodDelete:
			srv.handleClearErrors(w, r)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))

	// Endpoint pubblici dall'app
	mux.HandleFunc("/v1/errors", srv.handleReceiveError)
	mux.HandleFunc("/v1/tos/accept", srv.handleTosAccept)
	mux.HandleFunc("/v1/account", srv.handleDeleteAccount)

	// Endpoint interni (non esposti via nginx)
	mux.HandleFunc("/internal/whitelist/", srv.handleCheckWhitelist)
	mux.HandleFunc("/internal/gdpr", srv.handleGdprAccepted)
	mux.HandleFunc("/internal/presence/", srv.handlePresence)

	// Health check
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	// Job auto-scadenza: disattiva utenti con enabled_at > 1 anno fa
	go func() {
		for {
			res, err := db.Exec(`
				UPDATE whitelist SET enabled=false
				WHERE enabled=true AND enabled_at IS NOT NULL
				AND enabled_at < NOW() - INTERVAL '1 year'
			`)
			if err == nil {
				if n, _ := res.RowsAffected(); n > 0 {
					log.Printf("[ADMIN] Auto-scadenza: %d utenti disattivati", n)
				}
			}
			time.Sleep(6 * time.Hour)
		}
	}()

	log.Printf("[ADMIN] In ascolto su :%s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, mux); err != nil {
		log.Fatalf("[ADMIN] Server error: %v", err)
	}
}

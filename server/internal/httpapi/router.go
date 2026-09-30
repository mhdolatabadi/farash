package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

type healthResponse struct {
	Status string `json:"status"`
}

type Config struct {
	// AllowedOrigin is the web origin allowed to call the API cross-origin.
	AllowedOrigin string
	// Ping reports whether the database answers; nil skips the check.
	Ping func(context.Context) error
	// Store persists and reads authenticated users.
	Store userStore
	// AuthSecret signs HS256 JWTs.
	AuthSecret []byte
	// AuthTokenTTL controls the returned token lifetime.
	AuthTokenTTL time.Duration
	// Projects persists projects; nil leaves the project routes out.
	Projects projectStore
}

func NewHandler(config Config) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", health(config.Ping))

	if config.AuthTokenTTL == 0 {
		config.AuthTokenTTL = 24 * time.Hour
	}
	if config.Store != nil && len(config.AuthSecret) > 0 {
		auth := newAuthHandler(config.Store, config.AuthSecret, config.AuthTokenTTL)
		mux.HandleFunc("POST /api/v1/auth/register", auth.register)
		mux.HandleFunc("POST /api/v1/auth/login", auth.login)
		mux.HandleFunc("GET /api/v1/me", auth.me)
		if config.Projects != nil {
			(&projectHandler{auth: auth, projects: config.Projects}).routes(mux)
		}
	}

	mux.HandleFunc("/api/", func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, http.StatusNotFound, "not_found")
	})
	return cors(config.AllowedOrigin, mux)
}

func cors(allowedOrigin string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Add("Vary", "Origin")
		if allowedOrigin == "" || r.Header.Get("Origin") != allowedOrigin {
			next.ServeHTTP(w, r)
			return
		}
		w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Max-Age", "600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func health(ping func(context.Context) error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if ping != nil {
			if err := ping(r.Context()); err != nil {
				writeError(w, http.StatusServiceUnavailable, "database_unavailable")
				return
			}
		}
		writeJSON(w, http.StatusOK, healthResponse{Status: "ok"})
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

type errorResponse struct {
	Error string `json:"error"`
}

func writeError(w http.ResponseWriter, status int, code string) {
	writeJSON(w, status, errorResponse{Error: code})
}

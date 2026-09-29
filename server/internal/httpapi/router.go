package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
)

type healthResponse struct {
	Status string `json:"status"`
}

type Config struct {
	// AllowedOrigin is the web origin allowed to call the API cross-origin.
	AllowedOrigin string
	// Ping reports whether the database answers; nil skips the check.
	Ping func(context.Context) error
}

func NewHandler(config Config) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", health(config.Ping))
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

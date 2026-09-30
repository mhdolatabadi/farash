package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealth(t *testing.T) {
	handler := NewHandler(Config{Ping: func(context.Context) error { return nil }})
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/health", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Fatalf("body = %s", got)
	}
}

func TestHealthReportsDatabaseOutage(t *testing.T) {
	handler := NewHandler(Config{Ping: func(context.Context) error { return errors.New("down") }})
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/health", nil))

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "database_unavailable") {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestUnknownAPIPathIsJSON404(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(Config{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/nope", nil))

	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "not_found") {
		t.Fatalf("got %d %s", rec.Code, rec.Body.String())
	}
}

func TestCORSPreflight(t *testing.T) {
	handler := NewHandler(Config{AllowedOrigin: "https://todo.example.com"})
	req := httptest.NewRequest(http.MethodOptions, "/api/v1/health", nil)
	req.Header.Set("Origin", "https://todo.example.com")
	req.Header.Set("Access-Control-Request-Method", "PATCH")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status = %d, want 204", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://todo.example.com" {
		t.Fatalf("allow origin = %q", got)
	}
	if !strings.Contains(rec.Header().Get("Access-Control-Allow-Methods"), "PATCH") {
		t.Fatal("PATCH is not allowed")
	}
}

func TestCORSIgnoresOtherOrigins(t *testing.T) {
	handler := NewHandler(Config{AllowedOrigin: "https://todo.example.com"})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("allow origin = %q, want none", got)
	}
}

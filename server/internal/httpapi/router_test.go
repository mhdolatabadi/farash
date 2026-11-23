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

func TestPrivateAPIResponsesAreNeverHTTPSharedCached(t *testing.T) {
	handler := NewHandler(Config{
		AllowedOrigin: "https://todo.example.com",
		Store:         newFakeUsers(),
		AuthSecret:    []byte("test-secret"),
	})
	cases := []struct {
		name, method, path string
		origin, preflight  string
		wantStatus         int
	}{
		{"health success", http.MethodGet, "/api/v1/health", "", "", http.StatusOK},
		{"unauthorized private account", http.MethodGet, "/api/v1/me", "", "", http.StatusUnauthorized},
		{"invalid login", http.MethodPost, "/api/v1/auth/login", "", "", http.StatusBadRequest},
		{"unknown API path", http.MethodGet, "/api/v1/missing", "", "", http.StatusNotFound},
		{"allowed CORS preflight", http.MethodOptions, "/api/v1/me", "https://todo.example.com", "GET", http.StatusNoContent},
		{"untrusted origin", http.MethodGet, "/api/v1/me", "https://evil.example.com", "", http.StatusUnauthorized},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			if tc.origin != "" {
				req.Header.Set("Origin", tc.origin)
			}
			if tc.preflight != "" {
				req.Header.Set("Access-Control-Request-Method", tc.preflight)
			}
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)
			if rec.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tc.wantStatus)
			}
			if got := rec.Header().Get("Cache-Control"); got != "no-store" {
				t.Fatalf("Cache-Control = %q, want no-store", got)
			}
			if tc.origin == "https://evil.example.com" && rec.Header().Get("Access-Control-Allow-Origin") != "" {
				t.Fatal("untrusted origin received CORS access")
			}
		})
	}
}

func TestNonAPIRoutesDoNotInheritPrivateCachePolicy(t *testing.T) {
	rec := httptest.NewRecorder()
	NewHandler(Config{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/outside", nil))
	if got := rec.Header().Get("Cache-Control"); got != "" {
		t.Fatalf("unexpected Cache-Control outside API: %q", got)
	}
}

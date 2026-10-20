package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type exportUsers struct {
	*fakeUsers
	err   error
	owner string
	calls int
}

func (s *exportUsers) ExportAccount(_ context.Context, owner string) ([]byte, error) {
	s.owner = owner
	s.calls++
	return []byte(`{"format":"farash-export","version":1,"records":{}}`), s.err
}

func TestExportAuthenticationHeadersAndRateLimit(t *testing.T) {
	data := &exportUsers{fakeUsers: newFakeUsers()}
	api := &dbAPI{t: t, handler: NewHandler(Config{Store: data, AuthSecret: []byte("test-secret")})}
	token := api.register("export@example.com")
	other := api.register("other-export@example.com")
	request := func(token, path string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(http.MethodGet, path, nil)
		if token != "" {
			r.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		api.handler.ServeHTTP(w, r)
		if w.Header().Get("Cache-Control") != "no-store, private" {
			t.Fatal("export may be cached")
		}
		return w
	}
	if w := request("", "/api/v1/export"); w.Code != 401 || data.calls != 0 {
		t.Fatalf("unauthenticated: %d", w.Code)
	}
	if w := request(token, "/api/v1/export?owner_id=other"); w.Code != 400 || data.calls != 0 {
		t.Fatalf("caller-selected owner: %d", w.Code)
	}
	w := request(token, "/api/v1/export")
	if w.Code != 200 || data.owner == "" || w.Header().Get("Content-Disposition") != `attachment; filename="farash-export-v1.json"` || w.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("download contract: %d %v", w.Code, w.Header())
	}
	firstOwner := data.owner
	if w := request(token, "/api/v1/export"); w.Code != 200 {
		t.Fatalf("second download: %d", w.Code)
	}
	if w := request(token, "/api/v1/export"); w.Code != 429 || w.Header().Get("Retry-After") != "60" || data.calls != 2 {
		t.Fatalf("rate limiting: %d calls=%d", w.Code, data.calls)
	}
	if w := request(other, "/api/v1/export"); w.Code != 200 || data.owner == firstOwner {
		t.Fatalf("independent account: %d", w.Code)
	}
}

func TestExportFailuresDoNotProduceDownload(t *testing.T) {
	for _, test := range []struct {
		name string
		err  error
		code int
	}{
		{"size", store.ErrExportTooLarge, 413},
		{"timeout", context.DeadlineExceeded, 503},
		{"database", errors.New("private database error"), 500},
	} {
		t.Run(test.name, func(t *testing.T) {
			data := &exportUsers{fakeUsers: newFakeUsers(), err: test.err}
			api := &dbAPI{t: t, handler: NewHandler(Config{Store: data, AuthSecret: []byte("test-secret")})}
			token := api.register("failure-export@example.com")
			var response map[string]string
			if code := api.do("GET", "/api/v1/export", token, nil, &response); code != test.code {
				t.Fatalf("status: %d response=%v", code, response)
			}
			if response["error"] == "" || response["error"] == test.err.Error() {
				t.Fatalf("failure disclosure: %v", response)
			}
		})
	}
}

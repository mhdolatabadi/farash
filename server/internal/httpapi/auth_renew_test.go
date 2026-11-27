package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

// Compose both interfaces to exercise production route registration.
type renewableFakeUsers struct {
	*fakeUsers
	*fakeRefreshSessions
}

func TestRenewValidLegacyBearerCreatesRefreshableSession(t *testing.T) {
	secret := []byte("test-secret")
	users := newFakeUsers()
	users.byID["u1"] = store.User{ID: "u1", Email: "test@example.com"}
	refresh := &fakeRefreshSessions{tokens: make(map[string]string)}
	handler := NewHandler(Config{
		Store:        &renewableFakeUsers{users, refresh},
		AuthSecret:   secret,
		AuthTokenTTL: 24 * time.Hour,
	})
	old, err := signClaims(tokenClaims{
		Subject: "u1",
		Email:   "test@example.com",
		Expires: time.Now().Add(time.Hour).Unix(),
	}, secret)
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/renew", nil)
	request.Header.Set("Authorization", "Bearer "+old)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("renew = %d: %s", response.Code, response.Body.String())
	}
	var session authResponse
	if err := json.Unmarshal(response.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	if session.Token == "" || session.Token == old || session.RefreshToken == "" || session.User.ID != "u1" {
		t.Fatalf("legacy token was not upgraded: %+v", session)
	}
	claims, err := verifyToken(session.Token, secret)
	if err != nil || claims.Subject != "u1" {
		t.Fatalf("new bearer invalid: %+v, %v", claims, err)
	}
	if refresh.tokens[refreshDigest(session.RefreshToken)] != "u1" {
		t.Fatal("new refresh credential was not saved for the owner")
	}

	// The new credential can be rotated through the existing endpoint.
	body, err := json.Marshal(map[string]string{"refresh_token": session.RefreshToken})
	if err != nil {
		t.Fatal(err)
	}
	rotated := postJSON(handler, "/api/v1/auth/refresh", string(body), "")
	if rotated.Code != http.StatusOK {
		t.Fatalf("rotated legacy session = %d: %s", rotated.Code, rotated.Body.String())
	}
}

func TestRenewRejectsExpiredForgedAndMissingBearers(t *testing.T) {
	secret := []byte("test-secret")
	users := newFakeUsers()
	users.byID["u1"] = store.User{ID: "u1", Email: "test@example.com"}
	refresh := &fakeRefreshSessions{tokens: make(map[string]string)}
	handler := NewHandler(Config{
		Store:      &renewableFakeUsers{users, refresh},
		AuthSecret: secret,
	})
	expired, err := signClaims(tokenClaims{
		Subject: "u1", Expires: time.Now().Add(-time.Minute).Unix(),
	}, secret)
	if err != nil {
		t.Fatal(err)
	}
	for _, bearer := range []string{"", "invalid", expired} {
		request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/renew", nil)
		if bearer != "" {
			request.Header.Set("Authorization", "Bearer "+bearer)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("accepted %q: %d %s", bearer, response.Code, response.Body.String())
		}
	}
	if len(refresh.tokens) != 0 {
		t.Fatal("invalid bearer created a refresh session")
	}
}

func TestRenewWithoutRefreshStorageFailsClosed(t *testing.T) {
	users := newFakeUsers()
	users.byID["u1"] = store.User{ID: "u1", Email: "test@example.com"}
	handler := NewHandler(Config{
		Store:      users,
		AuthSecret: []byte("test-secret"),
	})
	token, err := signClaims(tokenClaims{
		Subject: "u1", Expires: time.Now().Add(time.Hour).Unix(),
	}, []byte("test-secret"))
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/renew", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusNotImplemented {
		t.Fatalf("renew without refresh store = %d: %s", response.Code, response.Body.String())
	}
}

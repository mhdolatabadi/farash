package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type fakeUsers struct {
	byID    map[string]store.User
	byEmail map[string]store.User
}

func newFakeUsers() *fakeUsers {
	return &fakeUsers{byID: map[string]store.User{}, byEmail: map[string]store.User{}}
}

func (f *fakeUsers) CreateUser(_ context.Context, email string, hash string) (store.User, error) {
	email = store.NormalizeEmail(email)
	if _, exists := f.byEmail[email]; exists {
		return store.User{}, store.ErrEmailTaken
	}
	user := store.User{ID: "user-" + email, Email: email, PasswordHash: hash}
	f.byID[user.ID] = user
	f.byEmail[user.Email] = user
	return user, nil
}

func (f *fakeUsers) UserByEmail(_ context.Context, email string) (store.User, error) {
	user, ok := f.byEmail[store.NormalizeEmail(email)]
	if !ok {
		return store.User{}, store.ErrUserNotFound
	}
	return user, nil
}

func (f *fakeUsers) UserByID(_ context.Context, id string) (store.User, error) {
	user, ok := f.byID[id]
	if !ok {
		return store.User{}, store.ErrUserNotFound
	}
	return user, nil
}

func TestRegisterLoginAndMe(t *testing.T) {
	users := newFakeUsers()
	handler := NewHandler(Config{
		Store:        users,
		AuthSecret:   []byte("test-secret"),
		AuthTokenTTL: time.Hour,
	})

	register := postJSON(handler, "/api/v1/auth/register", `{"email":" Test@Example.COM ","password":"correct horse"}`, "")
	if register.Code != http.StatusCreated {
		t.Fatalf("register status = %d body = %s", register.Code, register.Body.String())
	}
	var created authResponse
	if err := json.NewDecoder(register.Body).Decode(&created); err != nil {
		t.Fatal(err)
	}
	if created.User.Email != "test@example.com" || created.Token == "" {
		t.Fatalf("unexpected response: %+v", created)
	}

	login := postJSON(handler, "/api/v1/auth/login", `{"email":"test@example.com","password":"correct horse"}`, "")
	if login.Code != http.StatusOK {
		t.Fatalf("login status = %d body = %s", login.Code, login.Body.String())
	}
	var session authResponse
	if err := json.NewDecoder(login.Body).Decode(&session); err != nil {
		t.Fatal(err)
	}

	me := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set("Authorization", "Bearer "+session.Token)
	handler.ServeHTTP(me, req)
	if me.Code != http.StatusOK || !strings.Contains(me.Body.String(), "test@example.com") {
		t.Fatalf("me = %d %s", me.Code, me.Body.String())
	}
}

func TestRegisterValidationAndDuplicateEmail(t *testing.T) {
	users := newFakeUsers()
	handler := NewHandler(Config{Store: users, AuthSecret: []byte("test-secret")})

	shortPassword := postJSON(handler, "/api/v1/auth/register", `{"email":"bad","password":"short"}`, "")
	if shortPassword.Code != http.StatusBadRequest || !strings.Contains(shortPassword.Body.String(), "invalid_email") {
		t.Fatalf("invalid request = %d %s", shortPassword.Code, shortPassword.Body.String())
	}

	first := postJSON(handler, "/api/v1/auth/register", `{"email":"a@example.com","password":"long-enough"}`, "")
	if first.Code != http.StatusCreated {
		t.Fatalf("first register = %d %s", first.Code, first.Body.String())
	}

	duplicate := postJSON(handler, "/api/v1/auth/register", `{"email":"A@example.com","password":"long-enough"}`, "")
	if duplicate.Code != http.StatusConflict || !strings.Contains(duplicate.Body.String(), "email_taken") {
		t.Fatalf("duplicate = %d %s", duplicate.Code, duplicate.Body.String())
	}
}

func TestLoginRejectsInvalidCredentials(t *testing.T) {
	hash, err := bcrypt.GenerateFromPassword([]byte("right-password"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatal(err)
	}
	users := newFakeUsers()
	users.byEmail["a@example.com"] = store.User{ID: "u1", Email: "a@example.com", PasswordHash: string(hash)}
	users.byID["u1"] = users.byEmail["a@example.com"]

	handler := NewHandler(Config{Store: users, AuthSecret: []byte("test-secret")})
	rec := postJSON(handler, "/api/v1/auth/login", `{"email":"a@example.com","password":"wrong-password"}`, "")
	if rec.Code != http.StatusUnauthorized || !strings.Contains(rec.Body.String(), "invalid_credentials") {
		t.Fatalf("login = %d %s", rec.Code, rec.Body.String())
	}
}

func TestMeRejectsBadToken(t *testing.T) {
	handler := NewHandler(Config{Store: newFakeUsers(), AuthSecret: []byte("test-secret")})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set("Authorization", "Bearer nope")
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized || !strings.Contains(rec.Body.String(), "invalid_token") {
		t.Fatalf("me = %d %s", rec.Code, rec.Body.String())
	}
}

func TestRateLimit(t *testing.T) {
	users := newFakeUsers()
	auth := newAuthHandler(users, []byte("test-secret"), time.Hour)
	auth.rateLimits = newRateLimiter(1, time.Minute)
	handler := http.HandlerFunc(auth.login)

	first := postJSON(handler, "/api/v1/auth/login", `{"email":"missing@example.com","password":"long-enough"}`, "1.2.3.4:5")
	if first.Code != http.StatusUnauthorized {
		t.Fatalf("first = %d", first.Code)
	}
	second := postJSON(handler, "/api/v1/auth/login", `{"email":"missing@example.com","password":"long-enough"}`, "1.2.3.4:5")
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second = %d %s", second.Code, second.Body.String())
	}
}

func postJSON(handler http.Handler, path string, body string, remoteAddr string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if remoteAddr != "" {
		req.RemoteAddr = remoteAddr
	}
	handler.ServeHTTP(rec, req)
	return rec
}

func TestVerifyExpiredToken(t *testing.T) {
	token, err := signClaims(tokenClaims{Subject: "u1", Expires: time.Now().Add(-time.Minute).Unix()}, []byte("secret"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := verifyToken(token, []byte("secret")); !errors.Is(err, errors.New("expired token")) && err == nil {
		t.Fatal("expired token verified")
	}
}

type fakeRefreshSessions struct {
	tokens map[string]string
}

func (f *fakeRefreshSessions) CreateRefreshSession(_ context.Context, userID, digest string, _ time.Time) error {
	f.tokens[digest] = userID
	return nil
}
func (f *fakeRefreshSessions) RotateRefreshSession(_ context.Context, old, next string, _ time.Time) (string, error) {
	userID, ok := f.tokens[old]
	if !ok {
		return "", store.ErrRefreshInvalid
	}
	delete(f.tokens, old)
	f.tokens[next] = userID
	return userID, nil
}
func (f *fakeRefreshSessions) RevokeRefreshSession(_ context.Context, digest string) error {
	delete(f.tokens, digest)
	return nil
}

func TestRefreshRotationRejectsReplayAndRevokes(t *testing.T) {
	users := newFakeUsers()
	users.byID["u1"] = store.User{ID: "u1", Email: "test@example.com"}
	refresh := &fakeRefreshSessions{tokens: make(map[string]string)}
	// Exercise the same handler with a session store attached.
	auth := newAuthHandler(users, []byte("test-secret"), time.Hour)
	auth.refreshStore = refresh
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/auth/refresh", auth.refresh)
	mux.HandleFunc("POST /api/v1/auth/revoke", auth.revoke)
	if err := refresh.CreateRefreshSession(context.Background(), "u1", refreshDigest("original"), time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	first := postJSON(mux, "/api/v1/auth/refresh", `{"refresh_token":"original"}`, "")
	if first.Code != http.StatusOK {
		t.Fatalf("refresh status = %d: %s", first.Code, first.Body.String())
	}
	var rotated authResponse
	if err := json.Unmarshal(first.Body.Bytes(), &rotated); err != nil {
		t.Fatal(err)
	}
	if rotated.RefreshToken == "" || rotated.RefreshToken == "original" {
		t.Fatal("token not rotated")
	}
	replay := postJSON(mux, "/api/v1/auth/refresh", `{"refresh_token":"original"}`, "")
	if replay.Code != http.StatusUnauthorized {
		t.Fatalf("replay accepted: %d", replay.Code)
	}
	revoke := postJSON(mux, "/api/v1/auth/revoke", `{"refresh_token":"`+rotated.RefreshToken+`"}`, "")
	if revoke.Code != http.StatusNoContent {
		t.Fatalf("revoke = %d", revoke.Code)
	}
	after := postJSON(mux, "/api/v1/auth/refresh", `{"refresh_token":"`+rotated.RefreshToken+`"}`, "")
	if after.Code != http.StatusUnauthorized {
		t.Fatalf("revoked token accepted: %d", after.Code)
	}
}

func TestLoginRateLimitCannotBeBypassedBySpoofingForwardedIP(t *testing.T) {
	auth := newAuthHandler(newFakeUsers(), []byte("test-secret"), time.Hour)
	auth.rateLimits = newRateLimiter(2, time.Minute)
	handler := http.HandlerFunc(auth.login)

	for attempt := 0; attempt < 3; attempt++ {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login",
			strings.NewReader(`{"email":"Victim@Example.com","password":"wrong-password"}`))
		req.Header.Set("X-Forwarded-For", fmt.Sprintf("198.51.100.%d", attempt+1))
		req.RemoteAddr = fmt.Sprintf("192.0.2.%d:12345", attempt+1)
		handler.ServeHTTP(rec, req)
		want := http.StatusUnauthorized
		if attempt == 2 {
			want = http.StatusTooManyRequests
		}
		if rec.Code != want {
			t.Fatalf("attempt %d: got %d, want %d", attempt+1, rec.Code, want)
		}
	}
}

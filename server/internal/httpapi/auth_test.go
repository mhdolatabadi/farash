package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
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

func TestRateLimiterBoundsUniqueKeysWithoutEvictingActiveClients(t *testing.T) {
	limiter := newRateLimiter(1, time.Hour)
	for i := 0; i < maxRateLimitBuckets; i++ {
		if !limiter.allow(strconv.Itoa(i)) {
			t.Fatalf("rejected key %d before capacity", i)
		}
	}
	if limiter.allow("overflow") {
		t.Fatal("new key bypassed capacity limit")
	}
	if len(limiter.buckets) != maxRateLimitBuckets {
		t.Fatalf("unexpected bucket count: %d", len(limiter.buckets))
	}
	if limiter.allow("0") {
		t.Fatal("existing throttled client was evicted at capacity")
	}
}

func TestRateLimiterReclaimsExpiredBucketsAtCapacity(t *testing.T) {
	limiter := newRateLimiter(1, time.Hour)
	for i := 0; i < maxRateLimitBuckets; i++ {
		limiter.buckets[strconv.Itoa(i)] = rateBucket{
			Reset: time.Now().Add(-time.Second),
			Count: 1,
		}
	}
	if !limiter.allow("recovered") {
		t.Fatal("expired buckets prevented a new client")
	}
	if len(limiter.buckets) != 1 {
		t.Fatalf("expired buckets not reclaimed: %d", len(limiter.buckets))
	}
	if limiter.allow("recovered") {
		t.Fatal("new client bypassed its own limit")
	}
}

func TestRateLimiterExpiredExistingKeyCanRetryAtCapacity(t *testing.T) {
	limiter := newRateLimiter(1, time.Hour)
	limiter.buckets["recovered"] = rateBucket{
		Reset: time.Now().Add(-time.Second),
		Count: 1,
	}
	for i := 1; i < maxRateLimitBuckets; i++ {
		limiter.buckets[strconv.Itoa(i)] = rateBucket{
			Reset: time.Now().Add(time.Hour),
			Count: 1,
		}
	}
	if !limiter.allow("recovered") {
		t.Fatal("expired existing client could not retry")
	}
	if len(limiter.buckets) != maxRateLimitBuckets {
		t.Fatalf("unexpected bucket count: %d", len(limiter.buckets))
	}
}

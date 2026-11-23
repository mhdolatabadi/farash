package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
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

type failingLookupUsers struct {
	*fakeUsers
}

func (f *failingLookupUsers) UserByEmail(_ context.Context, _ string) (store.User, error) {
	return store.User{}, errors.New("database unavailable")
}

func TestLoginUnknownAccountVerifiesDummyHash(t *testing.T) {
	// This must remain a valid bcrypt hash, otherwise an unknown account
	// would again skip the expensive password verification.
	if err := bcrypt.CompareHashAndPassword(
		[]byte(unknownAccountPasswordHash),
		[]byte("farash-invalid-account-dummy"),
	); err != nil {
		t.Fatalf("dummy bcrypt hash invalid: %v", err)
	}

	handler := NewHandler(Config{Store: newFakeUsers(), AuthSecret: []byte("test-secret")})
	for _, password := range []string{"long-enough", "farash-invalid-account-dummy"} {
		body, err := json.Marshal(authRequest{Email: "missing@example.com", Password: password})
		if err != nil {
			t.Fatal(err)
		}
		rec := postJSON(handler, "/api/v1/auth/login", string(body), "")
		if rec.Code != http.StatusUnauthorized || !strings.Contains(rec.Body.String(), "invalid_credentials") {
			t.Fatalf("unknown account with password %q = %d %s", password, rec.Code, rec.Body.String())
		}
	}
}

func TestLoginDatabaseFailureIsNotInvalidCredentials(t *testing.T) {
	users := &failingLookupUsers{fakeUsers: newFakeUsers()}
	handler := NewHandler(Config{Store: users, AuthSecret: []byte("test-secret")})
	rec := postJSON(handler, "/api/v1/auth/login",
		`{"email":"user@example.com","password":"long-enough"}`, "")
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), "user_lookup_failed") {
		t.Fatalf("database failure = %d %s", rec.Code, rec.Body.String())
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

func TestVerifyTokenRejectsUnsupportedProtectedHeaders(t *testing.T) {
	secret := []byte("test-secret")
	claims := tokenClaims{Subject: "u1", Expires: time.Now().Add(time.Hour).Unix()}
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name   string
		header string
		valid  bool
	}{
		{name: "supported", header: `{"alg":"HS256","typ":"JWT"}`, valid: true},
		{name: "wrong algorithm", header: `{"alg":"none","typ":"JWT"}`},
		{name: "wrong type", header: `{"alg":"HS256","typ":"other"}`},
		{name: "missing type", header: `{"alg":"HS256"}`},
		{name: "extra field", header: `{"alg":"HS256","typ":"JWT","kid":"untrusted"}`},
		{name: "invalid JSON", header: `not-json`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			unsigned := base64.RawURLEncoding.EncodeToString([]byte(tc.header)) +
				"." + base64.RawURLEncoding.EncodeToString(payload)
			token := unsigned + "." + sign(unsigned, secret)
			_, err := verifyToken(token, secret)
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v, verification error=%v", tc.valid, err)
			}
		})
	}
}

func TestVerifyTokenRejectsOversizedBearer(t *testing.T) {
	_, err := verifyToken(strings.Repeat("x", 4097), []byte("test-secret"))
	if err == nil {
		t.Fatal("oversized bearer token accepted")
	}
}

func TestAuthRequestRejectsOversizeAndTrailingJSON(t *testing.T) {
	const valid = `{"email":"test@example.com","password":"long-enough"}`
	tests := []struct {
		name string
		body string
		want int
	}{
		{name: "valid request", body: valid, want: http.StatusCreated},
		{name: "trailing whitespace", body: valid + "  \n\t", want: http.StatusCreated},
		{name: "second JSON object", body: valid + `{}`, want: http.StatusBadRequest},
		{name: "trailing invalid characters", body: valid + " trailing", want: http.StatusBadRequest},
		{name: "oversized body", body: valid + strings.Repeat(" ", maxAuthRequestBytes), want: http.StatusBadRequest},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Fresh handler avoids account and rate-limit state leaking between cases.
			handler := NewHandler(Config{Store: newFakeUsers(), AuthSecret: []byte("test-secret")})
			response := postJSON(handler, "/api/v1/auth/register", tc.body, "")
			if response.Code != tc.want {
				t.Fatalf("status = %d, want %d: %s", response.Code, tc.want, response.Body.String())
			}
			if tc.want == http.StatusBadRequest && !strings.Contains(response.Body.String(), "invalid_json") {
				t.Fatalf("expected invalid_json, got %s", response.Body.String())
			}
		})
	}
}

func TestLoginRejectsOversizedAndTrailingJSON(t *testing.T) {
	const valid = `{"email":"missing@example.com","password":"long-enough"}`
	for _, body := range []string{valid + `{}`, valid + strings.Repeat(" ", maxAuthRequestBytes)} {
		handler := NewHandler(Config{Store: newFakeUsers(), AuthSecret: []byte("test-secret")})
		response := postJSON(handler, "/api/v1/auth/login", body, "")
		if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), "invalid_json") {
			t.Fatalf("login accepted malformed input: %d %s", response.Code, response.Body.String())
		}
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

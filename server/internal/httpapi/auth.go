package httpapi

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type userStore interface {
	CreateUser(context.Context, string, string) (store.User, error)
	UserByEmail(context.Context, string) (store.User, error)
	UserByID(context.Context, string) (store.User, error)
}

type refreshSessionStore interface {
	CreateRefreshSession(context.Context, string, string, time.Time) error
	RotateRefreshSession(context.Context, string, string, time.Time) (string, error)
	RevokeRefreshSession(context.Context, string) error
}

type authHandler struct {
	refreshStore refreshSessionStore
	store        userStore
	secret       []byte
	tokenTTL     time.Duration
	rateLimits   *rateLimiter
}

type authRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type userResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

type authResponse struct {
	RefreshToken string       `json:"refresh_token,omitempty"`
	Token        string       `json:"token"`
	User         userResponse `json:"user"`
}

func newAuthHandler(store userStore, secret []byte, tokenTTL time.Duration) *authHandler {
	return &authHandler{
		store:      store,
		secret:     secret,
		tokenTTL:   tokenTTL,
		rateLimits: newRateLimiter(8, time.Minute),
	}
}

func (h *authHandler) register(w http.ResponseWriter, r *http.Request) {
	if !h.rateLimits.allow(clientKey(r, "register")) {
		writeError(w, http.StatusTooManyRequests, "rate_limited")
		return
	}
	request, ok := decodeAuthRequest(w, r)
	if !ok {
		return
	}
	if code := validateAuthRequest(request); code != "" {
		writeError(w, http.StatusBadRequest, code)
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(request.Password), bcrypt.DefaultCost)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "password_hash_failed")
		return
	}
	user, err := h.store.CreateUser(r.Context(), request.Email, string(hash))
	if err != nil {
		if errors.Is(err, store.ErrEmailTaken) {
			writeError(w, http.StatusConflict, "email_taken")
			return
		}
		writeError(w, http.StatusInternalServerError, "user_create_failed")
		return
	}
	h.writeAuth(w, r.Context(), http.StatusCreated, user)
}

func (h *authHandler) login(w http.ResponseWriter, r *http.Request) {
	if !h.rateLimits.allow(clientKey(r, "login")) {
		writeError(w, http.StatusTooManyRequests, "rate_limited")
		return
	}
	request, ok := decodeAuthRequest(w, r)
	if !ok {
		return
	}
	if code := validateAuthRequest(request); code != "" {
		writeError(w, http.StatusBadRequest, code)
		return
	}
	// A caller can forge X-Forwarded-For; additionally limit by the
	// normalized account identifier so rotating headers cannot brute-force
	// one account. This avoids treating all Caddy users as one IP bucket.
	if !h.rateLimits.allow("login-account:" + request.Email) {
		writeError(w, http.StatusTooManyRequests, "rate_limited")
		return
	}
	user, err := h.store.UserByEmail(r.Context(), request.Email)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_credentials")
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(request.Password)); err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_credentials")
		return
	}
	h.writeAuth(w, r.Context(), http.StatusOK, user)
}

func (h *authHandler) me(w http.ResponseWriter, r *http.Request) {
	user, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, map[string]userResponse{"user": publicUser(user)})
}

func refreshDigest(token string) string {
	digest := sha256.Sum256([]byte(token))
	return hex.EncodeToString(digest[:])
}

func newRefreshToken() (string, error) {
	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw[:]), nil
}

func (h *authHandler) refresh(w http.ResponseWriter, r *http.Request) {
	if h.refreshStore == nil {
		writeError(w, http.StatusNotImplemented, "refresh_unavailable")
		return
	}
	var request struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&request); err != nil || request.RefreshToken == "" {
		writeError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	next, err := newRefreshToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_generation_failed")
		return
	}
	userID, err := h.refreshStore.RotateRefreshSession(r.Context(), refreshDigest(request.RefreshToken), refreshDigest(next), time.Now().Add(90*24*time.Hour))
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_refresh_token")
		return
	}
	user, err := h.store.UserByID(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_refresh_token")
		return
	}
	token, err := h.signToken(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_sign_failed")
		return
	}
	writeJSON(w, http.StatusOK, authResponse{Token: token, RefreshToken: next, User: publicUser(user)})
}

func (h *authHandler) revoke(w http.ResponseWriter, r *http.Request) {
	if h.refreshStore == nil {
		writeError(w, http.StatusNotImplemented, "refresh_unavailable")
		return
	}
	var request struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&request); err != nil || request.RefreshToken == "" {
		writeError(w, http.StatusBadRequest, "invalid_request")
		return
	}
	if err := h.refreshStore.RevokeRefreshSession(r.Context(), refreshDigest(request.RefreshToken)); err != nil {
		writeError(w, http.StatusInternalServerError, "revoke_failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *authHandler) writeAuth(w http.ResponseWriter, ctx context.Context, status int, user store.User) {
	token, err := h.signToken(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token_sign_failed")
		return
	}
	response := authResponse{Token: token, User: publicUser(user)}
	if h.refreshStore != nil {
		refresh, err := newRefreshToken()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "token_generation_failed")
			return
		}
		if err := h.refreshStore.CreateRefreshSession(ctx, user.ID, refreshDigest(refresh), time.Now().Add(90*24*time.Hour)); err != nil {
			writeError(w, http.StatusInternalServerError, "session_create_failed")
			return
		}
		response.RefreshToken = refresh
	}
	writeJSON(w, status, response)
}

func (h *authHandler) authenticate(w http.ResponseWriter, r *http.Request) (store.User, bool) {
	const prefix = "Bearer "
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, prefix) {
		writeError(w, http.StatusUnauthorized, "missing_token")
		return store.User{}, false
	}
	claims, err := verifyToken(strings.TrimPrefix(header, prefix), h.secret)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_token")
		return store.User{}, false
	}
	user, err := h.store.UserByID(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_token")
		return store.User{}, false
	}
	return user, true
}

func decodeAuthRequest(w http.ResponseWriter, r *http.Request) (authRequest, bool) {
	defer r.Body.Close()
	var request authRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return authRequest{}, false
	}
	request.Email = store.NormalizeEmail(request.Email)
	return request, true
}

func validateAuthRequest(request authRequest) string {
	if !strings.Contains(request.Email, "@") || len(request.Email) > 254 {
		return "invalid_email"
	}
	if len(request.Password) < 8 || len(request.Password) > 72 {
		return "invalid_password"
	}
	return ""
}

func publicUser(user store.User) userResponse {
	return userResponse{ID: user.ID, Email: user.Email}
}

type tokenClaims struct {
	Subject string `json:"sub"`
	Email   string `json:"email"`
	Expires int64  `json:"exp"`
}

func (h *authHandler) signToken(user store.User) (string, error) {
	claims := tokenClaims{
		Subject: user.ID,
		Email:   user.Email,
		Expires: time.Now().Add(h.tokenTTL).Unix(),
	}
	return signClaims(claims, h.secret)
}

func signClaims(claims tokenClaims, secret []byte) (string, error) {
	header, err := json.Marshal(map[string]string{"alg": "HS256", "typ": "JWT"})
	if err != nil {
		return "", err
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	signature := sign(unsigned, secret)
	return unsigned + "." + signature, nil
}

func verifyToken(token string, secret []byte) (tokenClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return tokenClaims{}, errors.New("invalid token shape")
	}
	unsigned := parts[0] + "." + parts[1]
	if !hmac.Equal([]byte(parts[2]), []byte(sign(unsigned, secret))) {
		return tokenClaims{}, errors.New("invalid signature")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return tokenClaims{}, err
	}
	var claims tokenClaims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return tokenClaims{}, err
	}
	if claims.Subject == "" || time.Now().Unix() >= claims.Expires {
		return tokenClaims{}, errors.New("expired token")
	}
	return claims, nil
}

func sign(unsigned string, secret []byte) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(unsigned))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

type rateLimiter struct {
	mu      sync.Mutex
	limit   int
	window  time.Duration
	buckets map[string]rateBucket
}

type rateBucket struct {
	Reset time.Time
	Count int
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{
		limit:   limit,
		window:  window,
		buckets: make(map[string]rateBucket),
	}
}

func (r *rateLimiter) allow(key string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	bucket := r.buckets[key]
	if bucket.Reset.IsZero() || now.After(bucket.Reset) {
		r.buckets[key] = rateBucket{Reset: now.Add(r.window), Count: 1}
		return true
	}
	if bucket.Count >= r.limit {
		return false
	}
	bucket.Count++
	r.buckets[key] = bucket
	return true
}

func clientKey(r *http.Request, action string) string {
	ip := r.Header.Get("X-Forwarded-For")
	if ip == "" {
		ip = r.RemoteAddr
	}
	if ip == "" {
		ip = "unknown"
	}
	return action + ":" + ip
}

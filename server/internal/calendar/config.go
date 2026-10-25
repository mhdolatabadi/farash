package calendar

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/url"
	"regexp"
	"strings"
)

type Config struct {
	ClientID, ClientSecret, CallbackURL, WebReturnURL, AndroidReturnURL, KeyID string
	Keys                                                                       map[string][]byte
}

func ConfigFromEnv(get func(string) string) (*Config, error) {
	enabled := get("CALENDAR_GOOGLE_ENABLED")
	if enabled == "" || enabled == "false" {
		return nil, nil
	}
	if enabled != "true" {
		return nil, errors.New("invalid calendar configuration")
	}
	c := &Config{ClientID: get("CALENDAR_GOOGLE_CLIENT_ID"), ClientSecret: get("CALENDAR_GOOGLE_CLIENT_SECRET"), CallbackURL: get("CALENDAR_GOOGLE_CALLBACK_URL"), WebReturnURL: get("CALENDAR_WEB_RETURN_URL"), AndroidReturnURL: get("CALENDAR_ANDROID_RETURN_URL"), KeyID: get("CALENDAR_TOKEN_KEY_ID"), Keys: map[string][]byte{}}
	var keys map[string]string
	if json.Unmarshal([]byte(get("CALENDAR_TOKEN_KEYS")), &keys) != nil {
		return nil, errors.New("invalid calendar configuration")
	}
	for id, value := range keys {
		key, err := base64.StdEncoding.DecodeString(value)
		if err != nil || len(key) != 32 || id == "" {
			return nil, errors.New("invalid calendar configuration")
		}
		c.Keys[id] = key
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return c, nil
}
func (c Config) Validate() error {
	fail := errors.New("invalid calendar configuration")
	if c.ClientID == "" || c.ClientSecret == "" || len(c.Keys[c.KeyID]) != 32 || !regexp.MustCompile(`^[A-Za-z0-9_-]{1,32}$`).MatchString(c.KeyID) {
		return fail
	}
	for _, s := range []string{c.CallbackURL, c.WebReturnURL, c.AndroidReturnURL} {
		u, e := url.Parse(s)
		if e != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
			return fail
		}
	}
	u, _ := url.Parse(c.CallbackURL)
	if u.Path != "/api/v1/calendar-connections/google/callback" {
		return fail
	}
	return nil
}
func (c Config) Origin() string { u, _ := url.Parse(c.CallbackURL); return u.Scheme + "://" + u.Host }
func (c Config) Seal(owner, purpose string, plain []byte) ([]byte, error) {
	block, e := aes.NewCipher(c.Keys[c.KeyID])
	if e != nil {
		return nil, e
	}
	a, e := cipher.NewGCM(block)
	if e != nil {
		return nil, e
	}
	n := make([]byte, a.NonceSize())
	if _, e = rand.Read(n); e != nil {
		return nil, e
	}
	data := a.Seal(n, n, plain, []byte(owner+"\x00"+purpose))
	return []byte(c.KeyID + ":" + base64.RawStdEncoding.EncodeToString(data)), nil
}
func (c Config) Open(owner, purpose string, data []byte) ([]byte, error) {
	id, value, ok := strings.Cut(string(data), ":")
	if !ok || len(c.Keys[id]) != 32 {
		return nil, ErrReconnect
	}
	raw, e := base64.RawStdEncoding.DecodeString(value)
	if e != nil {
		return nil, ErrReconnect
	}
	block, _ := aes.NewCipher(c.Keys[id])
	a, _ := cipher.NewGCM(block)
	if len(raw) < a.NonceSize() {
		return nil, ErrReconnect
	}
	plain, e := a.Open(nil, raw[:a.NonceSize()], raw[a.NonceSize():], []byte(owner+"\x00"+purpose))
	if e != nil {
		return nil, ErrReconnect
	}
	return plain, nil
}

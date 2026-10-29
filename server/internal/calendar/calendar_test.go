package calendar

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

func testConfig() Config {
	return Config{ClientID: "client", ClientSecret: "secret", CallbackURL: "https://api.example/api/v1/calendar-connections/google/callback", WebReturnURL: "https://app.example/", AndroidReturnURL: "https://app.example/calendar-return", KeyID: "one", Keys: map[string][]byte{"one": bytes.Repeat([]byte{7}, 32)}}
}
func TestConfigurationAndCredentialBinding(t *testing.T) {
	c := testConfig()
	if e := c.Validate(); e != nil {
		t.Fatal(e)
	}
	for _, v := range []string{"http://app.example/", "https://user@host/", "https://host/?redirect=x", "https://host/#x"} {
		bad := c
		bad.WebReturnURL = v
		if bad.Validate() == nil {
			t.Fatal("accepted unsafe return", v)
		}
	}
	value, e := c.Seal("alice", "connection:one", []byte("private"))
	if e != nil {
		t.Fatal(e)
	}
	if bytes.Contains(value, []byte("private")) {
		t.Fatal("plaintext stored")
	}
	for _, binding := range [][2]string{{"bob", "connection:one"}, {"alice", "connection:two"}} {
		if _, e = c.Open(binding[0], binding[1], value); e == nil {
			t.Fatal("unbound credential")
		}
	}
	next := c
	next.KeyID = "two"
	next.Keys["two"] = bytes.Repeat([]byte{8}, 32)
	if plain, e := next.Open("alice", "connection:one", value); e != nil || string(plain) != "private" {
		t.Fatal("key rotation", e)
	}
	value[len(value)-3] ^= 1
	if _, e = c.Open("alice", "connection:one", value); e == nil {
		t.Fatal("tamper accepted")
	}
	env := map[string]string{"CALENDAR_GOOGLE_ENABLED": "true", "CALENDAR_GOOGLE_CLIENT_ID": c.ClientID, "CALENDAR_GOOGLE_CLIENT_SECRET": c.ClientSecret, "CALENDAR_GOOGLE_CALLBACK_URL": c.CallbackURL, "CALENDAR_WEB_RETURN_URL": c.WebReturnURL, "CALENDAR_ANDROID_RETURN_URL": c.AndroidReturnURL, "CALENDAR_TOKEN_KEY_ID": "one", "CALENDAR_TOKEN_KEYS": `{"one":"` + base64.StdEncoding.EncodeToString(c.Keys["one"]) + `"}`}
	if _, e := ConfigFromEnv(func(k string) string { return env[k] }); e != nil {
		t.Fatal(e)
	}
	delete(env, "CALENDAR_TOKEN_KEYS")
	if _, e := ConfigFromEnv(func(k string) string { return env[k] }); e == nil {
		t.Fatal("enabled incomplete config")
	}
	if c, e := ConfigFromEnv(func(string) string { return "" }); e != nil || c != nil {
		t.Fatal("disabled", e)
	}
}

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func response(code int, body string) *http.Response {
	return &http.Response{StatusCode: code, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body))}
}
func TestGoogleFixedOriginsReadonlyScopesPKCEAndRefresh(t *testing.T) {
	c := testConfig()
	g := Google{Config: c}
	u, _ := url.Parse(g.AuthorizeURL("state", "challenge", false))
	if u.Host != "accounts.google.com" || u.Query().Get("scope") != ListScope+" "+EventsScope || u.Query().Get("code_challenge_method") != "S256" || u.Query().Get("prompt") != "" {
		t.Fatal(u)
	}
	g.HTTP = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		if r.URL.String() != "https://oauth2.googleapis.com/token" {
			t.Fatal("unexpected endpoint", r.URL)
		}
		if e := r.ParseForm(); e != nil {
			t.Fatal(e)
		}
		if r.Form.Get("refresh_token") != "old-refresh" || r.Form.Get("client_secret") != "secret" {
			t.Fatal("refresh request")
		}
		b, _ := json.Marshal(map[string]any{"access_token": "new-access", "expires_in": 3600, "token_type": "Bearer"})
		return response(200, string(b)), nil
	})}
	next, e := g.Refresh(context.Background(), Token{Access: "expired", Refresh: "old-refresh", Scope: ListScope + " " + EventsScope})
	if e != nil || next.Refresh != "old-refresh" || !hasScopes(next.Scope) {
		t.Fatal(next, e)
	}
	g.HTTP = &http.Client{Transport: transport(func(*http.Request) (*http.Response, error) {
		return response(400, `{"error":"invalid_grant","secret":"never propagate"}`), nil
	})}
	if _, e = g.Refresh(context.Background(), next); e != ErrReconnect {
		t.Fatal(e)
	}
}
func TestGoogleWindowUsesProviderExpansionPreservesDatesAndBounds(t *testing.T) {
	g := Google{Config: testConfig()}
	g.HTTP = &http.Client{Transport: transport(func(r *http.Request) (*http.Response, error) {
		q := r.URL.Query()
		if r.URL.Host != "www.googleapis.com" || q.Get("singleEvents") != "true" || q.Get("syncToken") != "" || q.Get("timeMin") == "" || q.Get("fields") == "" {
			t.Fatal(r.URL)
		}
		return response(200, `{"items":[{"id":"day","summary":"","status":"confirmed","start":{"date":"2026-10-25"},"end":{"date":"2026-10-27"}},{"id":"cancelled","status":"cancelled"}]}`), nil
	})}
	events, page, e := g.Events(context.Background(), Token{Access: "private"}, "primary", time.Now(), time.Now().Add(time.Hour), "")
	if e != nil || page != "" || len(events) != 1 || events[0].Start.Date != "2026-10-25" || events[0].End.Date != "2026-10-27" || events[0].Title != "مشغول" {
		t.Fatal(events, page, e)
	}
	g.HTTP = &http.Client{Transport: transport(func(*http.Request) (*http.Response, error) {
		return response(200, strings.Repeat(" ", 2*1024*1024+1)), nil
	})}
	if _, _, e = g.Calendars(context.Background(), Token{}, ""); e != ErrProvider {
		t.Fatal("unbounded body", e)
	}
}

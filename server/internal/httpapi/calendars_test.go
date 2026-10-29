package httpapi

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	cal "github.com/mhdolatabadi/farash/server/internal/calendar"
	"github.com/mhdolatabadi/farash/server/internal/store"
)

type calendarProvider struct {
	verifier, challenge string
	reads               int
	revokeFail          bool
}

func (p *calendarProvider) AuthorizeURL(state, challenge string, consent bool) string {
	p.challenge = challenge
	return "https://accounts.google.com/consent?state=" + state
}
func (p *calendarProvider) Exchange(_ context.Context, code, verifier string) (cal.Token, error) {
	p.verifier = verifier
	if code != "valid-code" {
		return cal.Token{}, cal.ErrReconnect
	}
	return cal.Token{Access: "private-access", Refresh: "private-refresh", Scope: cal.ListScope + " " + cal.EventsScope, Expiry: time.Now().Add(time.Hour)}, nil
}
func (p *calendarProvider) Refresh(_ context.Context, t cal.Token) (cal.Token, error) { return t, nil }
func (p *calendarProvider) Revoke(context.Context, cal.Token) error {
	if p.revokeFail {
		return errors.New("provider offline")
	}
	return nil
}
func (p *calendarProvider) Calendars(context.Context, cal.Token, string) ([]cal.Calendar, string, error) {
	p.reads++
	return []cal.Calendar{{ProviderID: "private-google-id", Title: "کار", TimeZone: "Asia/Tehran"}}, "", nil
}
func (p *calendarProvider) Events(context.Context, cal.Token, string, time.Time, time.Time, string) ([]cal.Event, string, error) {
	return []cal.Event{{ID: "google-event", Title: "جلسه", Start: cal.Moment{Date: "2026-10-25"}, End: cal.Moment{Date: "2026-10-27"}}}, "", nil
}
func newCalendarAPI(t *testing.T) (*dbAPI, *calendarProvider) {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	pool, e := pgxpool.New(ctx, dsn)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(pool.Close)
	if _, e = pool.Exec(ctx, `DROP SCHEMA public CASCADE;CREATE SCHEMA public`); e != nil {
		t.Fatal(e)
	}
	if e = store.Migrate(ctx, pool); e != nil {
		t.Fatal(e)
	}
	data := store.New(pool)
	provider := &calendarProvider{}
	config := cal.Config{ClientID: "client", ClientSecret: "secret", CallbackURL: "https://api.example/api/v1/calendar-connections/google/callback", WebReturnURL: "https://app.example/", AndroidReturnURL: "https://app.example/calendar-return", KeyID: "one", Keys: map[string][]byte{"one": make([]byte, 32)}}
	return &dbAPI{t: t, handler: NewHandler(Config{Store: data, AuthSecret: []byte("test-secret"), Calendar: &cal.Service{Repo: data, Provider: provider, Config: config}})}, provider
}
func TestCalendarDisabledIsAuthenticatedAndExplicit(t *testing.T) {
	api := &dbAPI{t: t, handler: NewHandler(Config{Store: newFakeUsers(), AuthSecret: []byte("test-secret")})}
	token := api.register("calendar-disabled@example.com")
	if code := api.do("GET", "/api/v1/calendar-connections", "", nil, nil); code != 401 {
		t.Fatal(code)
	}
	var out struct {
		Configured  bool
		Connections []cal.Connection
	}
	if code := api.do("GET", "/api/v1/calendar-connections", token, nil, &out); code != 200 || out.Configured || len(out.Connections) != 0 {
		t.Fatal(code, out)
	}
}
func TestCalendarBrokerAPIReadonlyPrivacyReplayAndRevocation(t *testing.T) {
	api, provider := newCalendarAPI(t)
	alice := api.register("calendar-alice@example.com")
	bob := api.register("calendar-bob@example.com")
	for _, body := range []any{map[string]any{"client": "evil", "return_url": "https://evil"}, map[string]any{"client": "web", "owner_id": "bob"}} {
		if code := api.do("POST", "/api/v1/calendar-connections/google/authorize", alice, body, nil); code != 400 {
			t.Fatal("validation", code)
		}
	}
	if code := api.do("POST", "/api/v1/calendar-connections/google/authorize", "", map[string]string{"client": "web"}, nil); code != 401 {
		t.Fatal(code)
	}
	var prepared struct {
		StartURL string `json:"start_url"`
	}
	if code := api.do("POST", "/api/v1/calendar-connections/google/authorize", alice, map[string]string{"client": "web"}, &prepared); code != 200 {
		t.Fatal(code)
	}
	startURL, e := url.Parse(prepared.StartURL)
	if e != nil || startURL.Host != "api.example" {
		t.Fatal(prepared, e)
	}
	start := httptest.NewRecorder()
	api.handler.ServeHTTP(start, httptest.NewRequest("GET", startURL.RequestURI(), nil))
	if start.Code != 303 || len(start.Result().Cookies()) != 1 {
		t.Fatal(start.Code, start.Body.String())
	}
	cookie := start.Result().Cookies()[0]
	if !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteLaxMode {
		t.Fatal("unsafe cookie")
	}
	authorize, _ := url.Parse(start.Header().Get("Location"))
	state := authorize.Query().Get("state")
	if len(state) != 43 {
		t.Fatal("state entropy")
	}
	callback := "/api/v1/calendar-connections/google/callback?state=" + state + "&code=valid-code"
	missing := httptest.NewRecorder()
	api.handler.ServeHTTP(missing, httptest.NewRequest("GET", callback, nil))
	if missing.Code != 400 {
		t.Fatal("cookie not required", missing.Code)
	}
	request := httptest.NewRequest("GET", callback, nil)
	request.AddCookie(cookie)
	complete := httptest.NewRecorder()
	api.handler.ServeHTTP(complete, request)
	if complete.Code != 303 || complete.Header().Get("Location") != "https://app.example/" {
		t.Fatal(complete.Code, complete.Body.String())
	}
	challengeBytes := sha256.Sum256([]byte(provider.verifier))
	if provider.challenge != base64.RawURLEncoding.EncodeToString(challengeBytes[:]) {
		t.Fatal("PKCE challenge mismatch")
	}
	if len(provider.verifier) != 43 || provider.challenge == "" {
		t.Fatal("PKCE missing")
	}
	if _, e = base64.RawURLEncoding.DecodeString(provider.challenge); e != nil {
		t.Fatal("invalid challenge")
	}
	replay := httptest.NewRecorder()
	api.handler.ServeHTTP(replay, request)
	if replay.Code != 404 {
		t.Fatal("callback replay", replay.Code)
	}
	var list struct {
		Configured  bool
		Connections []cal.Connection
	}
	if code := api.do("GET", "/api/v1/calendar-connections", alice, nil, &list); code != 200 || !list.Configured || len(list.Connections) != 1 {
		t.Fatal(code, list)
	}
	id := list.Connections[0].ID
	var foreign struct{ Connections []cal.Connection }
	api.do("GET", "/api/v1/calendar-connections", bob, nil, &foreign)
	if len(foreign.Connections) != 0 {
		t.Fatal("owner list leak")
	}
	if code := api.do("GET", "/api/v1/calendar-connections/"+id+"/calendars", bob, nil, nil); code != 404 || provider.reads != 0 {
		t.Fatal("foreign provider fetch", code, provider.reads)
	}
	var choices struct {
		Calendars []cal.Calendar
		Version   int64
	}
	if code := api.do("GET", "/api/v1/calendar-connections/"+id+"/calendars", alice, nil, &choices); code != 200 || len(choices.Calendars) != 1 {
		t.Fatal(code, choices)
	}
	encoded, _ := json.Marshal(choices)
	if strings.Contains(string(encoded), "private-google-id") {
		t.Fatal("provider id exposed")
	}
	if code := api.do("PUT", "/api/v1/calendar-connections/"+id+"/selection", alice, map[string]any{"calendar_ids": []string{choices.Calendars[0].ID}, "version": choices.Version}, nil); code != 200 {
		t.Fatal(code)
	}
	var overlay struct {
		Events   []cal.Event
		Complete bool
	}
	window := "/api/v1/calendar-connections/" + id + "/events?from=2026-10-25T00:00:00Z&to=2026-10-28T00:00:00Z"
	if code := api.do("GET", window, alice, nil, &overlay); code != 200 || !overlay.Complete || len(overlay.Events) != 1 || !overlay.Events[0].ReadOnly || overlay.Events[0].End.Date != "2026-10-27" {
		t.Fatal(code, overlay)
	}
	if code := api.do("GET", "/api/v1/calendar-connections/"+id+"/events?from=2020-01-01T00:00:00Z&to=2026-01-01T00:00:00Z", alice, nil, nil); code != 400 {
		t.Fatal("range cap", code)
	}
	if code := api.do("DELETE", "/api/v1/calendar-connections/"+id, bob, nil, nil); code != 404 {
		t.Fatal("foreign delete", code)
	}
	provider.revokeFail = true
	var disconnected struct{ Disconnected, Revoked bool }
	if code := api.do("DELETE", "/api/v1/calendar-connections/"+id, alice, nil, &disconnected); code != 200 || !disconnected.Disconnected || disconnected.Revoked {
		t.Fatal(code, disconnected)
	}
	if code := api.do("GET", window, alice, nil, nil); code != 404 {
		t.Fatal("local disconnect", code)
	}
}

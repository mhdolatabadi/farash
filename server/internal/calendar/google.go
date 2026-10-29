package calendar

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Google struct {
	Config Config
	HTTP   *http.Client
}

func (g *Google) client() *http.Client {
	if g.HTTP != nil {
		return g.HTTP
	}
	return &http.Client{Timeout: 20 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
}
func (g *Google) AuthorizeURL(state, challenge string, consent bool) string {
	q := url.Values{"client_id": {g.Config.ClientID}, "redirect_uri": {g.Config.CallbackURL}, "response_type": {"code"}, "scope": {ListScope + " " + EventsScope}, "access_type": {"offline"}, "state": {state}, "code_challenge": {challenge}, "code_challenge_method": {"S256"}}
	if consent {
		q.Set("prompt", "consent")
	}
	return "https://accounts.google.com/o/oauth2/v2/auth?" + q.Encode()
}
func (g *Google) request(ctx context.Context, method, endpoint string, form url.Values, access string, out any) error {
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	r, e := http.NewRequestWithContext(ctx, method, endpoint, body)
	if e != nil {
		return ErrProvider
	}
	if form != nil {
		r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	if access != "" {
		r.Header.Set("Authorization", "Bearer "+access)
	}
	res, e := g.client().Do(r)
	if e != nil {
		return ErrProvider
	}
	defer res.Body.Close()
	// Provider errors are never propagated: bodies may contain credential material.
	if res.StatusCode == 401 {
		return ErrReconnect
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		if res.StatusCode == 400 && strings.HasPrefix(endpoint, "https://oauth2.googleapis.com/token") {
			return ErrReconnect
		}
		return ErrProvider
	}
	if out == nil {
		_, _ = io.Copy(io.Discard, io.LimitReader(res.Body, 4096))
		return nil
	}
	data, e := io.ReadAll(io.LimitReader(res.Body, 2*1024*1024+1))
	if e != nil || len(data) > 2*1024*1024 || json.Unmarshal(data, out) != nil {
		return ErrProvider
	}
	return nil
}
func (g *Google) token(ctx context.Context, form url.Values, previous Token) (Token, error) {
	form.Set("client_id", g.Config.ClientID)
	form.Set("client_secret", g.Config.ClientSecret)
	var v struct {
		Access  string `json:"access_token"`
		Refresh string `json:"refresh_token"`
		Expires int    `json:"expires_in"`
		Scope   string `json:"scope"`
		Type    string `json:"token_type"`
	}
	if e := g.request(ctx, "POST", "https://oauth2.googleapis.com/token", form, "", &v); e != nil {
		return Token{}, e
	}
	if v.Access == "" || v.Expires <= 0 || v.Expires > 86400 || !strings.EqualFold(v.Type, "Bearer") {
		return Token{}, ErrProvider
	}
	if v.Refresh == "" {
		v.Refresh = previous.Refresh
	}
	if v.Scope == "" {
		v.Scope = previous.Scope
	}
	if !hasScopes(v.Scope) || v.Refresh == "" {
		return Token{}, ErrReconnect
	}
	return Token{Access: v.Access, Refresh: v.Refresh, Expiry: time.Now().Add(time.Duration(v.Expires) * time.Second), Scope: v.Scope}, nil
}
func hasScopes(scope string) bool {
	var a, b bool
	for _, s := range strings.Fields(scope) {
		a = a || s == ListScope
		b = b || s == EventsScope
	}
	return a && b
}
func (g *Google) Exchange(ctx context.Context, code, verifier string) (Token, error) {
	return g.token(ctx, url.Values{"grant_type": {"authorization_code"}, "code": {code}, "code_verifier": {verifier}, "redirect_uri": {g.Config.CallbackURL}}, Token{})
}
func (g *Google) Refresh(ctx context.Context, t Token) (Token, error) {
	return g.token(ctx, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {t.Refresh}}, t)
}
func (g *Google) Revoke(ctx context.Context, t Token) error {
	return g.request(ctx, "POST", "https://oauth2.googleapis.com/revoke", url.Values{"token": {t.Refresh}}, "", nil)
}
func (g *Google) Calendars(ctx context.Context, t Token, page string) ([]Calendar, string, error) {
	q := url.Values{"maxResults": {"250"}, "fields": {"nextPageToken,items(id,summary,timeZone)"}}
	if page != "" {
		q.Set("pageToken", page)
	}
	var v struct {
		Next  string                                   `json:"nextPageToken"`
		Items []struct{ ID, Summary, TimeZone string } `json:"items"`
	}
	if e := g.request(ctx, "GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList?"+q.Encode(), nil, t.Access, &v); e != nil {
		return nil, "", e
	}
	out := make([]Calendar, 0, len(v.Items))
	for _, c := range v.Items {
		if c.ID == "" || len(c.ID) > 1024 || len(c.Summary) > 2048 {
			return nil, "", ErrProvider
		}
		out = append(out, Calendar{ProviderID: c.ID, Title: c.Summary, TimeZone: c.TimeZone})
	}
	return out, v.Next, nil
}
func (g *Google) Events(ctx context.Context, t Token, id string, from, to time.Time, page string) ([]Event, string, error) {
	q := url.Values{"maxResults": {"500"}, "singleEvents": {"true"}, "showDeleted": {"false"}, "orderBy": {"startTime"}, "timeMin": {from.Format(time.RFC3339)}, "timeMax": {to.Format(time.RFC3339)}, "fields": {"nextPageToken,items(id,summary,status,start,end)"}}
	if page != "" {
		q.Set("pageToken", page)
	}
	var v struct {
		Next  string `json:"nextPageToken"`
		Items []struct {
			ID, Summary, Status string
			Start, End          Moment
		} `json:"items"`
	}
	if e := g.request(ctx, "GET", "https://www.googleapis.com/calendar/v3/calendars/"+url.PathEscape(id)+"/events?"+q.Encode(), nil, t.Access, &v); e != nil {
		return nil, "", e
	}
	out := make([]Event, 0, len(v.Items))
	for _, e := range v.Items {
		if e.Status == "cancelled" {
			continue
		}
		if e.ID == "" || len(e.ID) > 1024 || len(e.Summary) > 2048 || !validMoment(e.Start) || !validMoment(e.End) {
			return nil, "", ErrProvider
		}
		title := e.Summary
		if title == "" {
			title = "مشغول"
		}
		out = append(out, Event{ID: e.ID, Title: title, Start: e.Start, End: e.End, Status: e.Status, ReadOnly: true})
	}
	return out, v.Next, nil
}
func validMoment(m Moment) bool {
	if m.Date != "" && m.DateTime == "" {
		_, e := time.Parse("2006-01-02", m.Date)
		return e == nil
	}
	if m.DateTime != "" && m.Date == "" {
		_, e := time.Parse(time.RFC3339, m.DateTime)
		return e == nil
	}
	return false
}

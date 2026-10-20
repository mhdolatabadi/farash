package store

import (
	"strings"
	"testing"
)

func TestSearchNormalizationAndGrammar(t *testing.T) {
	if got := normalizeSearch("  مي\u200cكنم  Code "); got != "میکنمcode" {
		t.Fatal(got)
	}
	for _, query := range []string{"", "today", "امروز", "no date", "بدون تاریخ", "7 days", "۷روز", "p1 & (today | overdue)", "!@تلفن #کار", `#"کار شخصی"`, "##study", `"today"`, `"a & b"`, "foo bar"} {
		sql, args, err := compileSearch(query, "2026-10-21")
		if err != nil || sql == "" || len(args) < 1 {
			t.Fatalf("%q: %q %v %v", query, sql, args, err)
		}
	}
	for _, query := range []string{"(", ")", "p1 |", "& today", "p1 && p2", "#", "@", "##", `"unfinished`, "assigned:me", "p9", strings.Repeat("!", 40) + "today", strings.Repeat("a", 1001)} {
		if _, _, err := compileSearch(query, "2026-10-21"); err == nil {
			t.Errorf("accepted invalid query %q", query)
		}
	}
	for _, day := range []string{"", "2026-02-30", "0000-01-01", "2026-1-01"} {
		if _, _, err := compileSearch("today", day); err == nil {
			t.Errorf("accepted invalid civil day %q", day)
		}
	}
	sql, args, err := compileSearch(`"x'); DROP TABLE tasks; --"`, "2026-10-21")
	if err != nil || strings.Contains(sql, "DROP") || args[1] != "x');droptabletasks;--" {
		t.Fatal("query values must remain bound", sql, args, err)
	}
	sql, _, _ = compileSearch("p1 | p2 & today", "2026-10-21")
	if !strings.Contains(sql, "OR (priority=$4 AND due_date=$2::date)") {
		t.Fatal("AND precedence", sql)
	}
}

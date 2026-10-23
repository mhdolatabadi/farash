package store

import (
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"
)

var ErrInvalidSearch = errors.New("invalid search")

// SearchOptions uses a caller-supplied civil day. The server never guesses the
// user's timezone when evaluating today, overdue or the next seven days.
type SearchOptions struct {
	Query         string
	Today         string
	ShowCompleted bool
	Sort          string
	Limit         int
	Offset        int
}

func normalizeSearch(value string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case 'ي', 'ى':
			return 'ی'
		case 'ك':
			return 'ک'
		case '\u200c':
			return -1
		}
		if unicode.IsSpace(r) {
			return -1
		}
		return unicode.ToLower(r)
	}, value)
}

// SQL normalization mirrors the Persian letters and spacing accepted by the
// parser. Search is literal substring matching, never user-provided SQL/regex.
func normalizedSQL(column string) string {
	return "regexp_replace(lower(translate(" + column + ", 'يىك', 'ییک')), '[[:space:]‌]+', '', 'g')"
}

type searchToken struct {
	value  string
	quoted bool
}

type searchParser struct {
	tokens []searchToken
	index  int
	args   []any
	today  string
	depth  int
}

func tokenizeSearch(query string) ([]searchToken, error) {
	if len([]rune(query)) > 1000 {
		return nil, ErrInvalidSearch
	}
	tokens := []searchToken{}
	runes := []rune(query)
	for i := 0; i < len(runes); {
		if unicode.IsSpace(runes[i]) {
			i++
			continue
		}
		if strings.ContainsRune("&|!()", runes[i]) {
			tokens = append(tokens, searchToken{value: string(runes[i])})
			i++
			continue
		}
		var value strings.Builder
		quoted := false
		for i < len(runes) && !unicode.IsSpace(runes[i]) && !strings.ContainsRune("&|!()", runes[i]) {
			if runes[i] != '"' {
				value.WriteRune(runes[i])
				i++
				continue
			}
			quoted = true
			i++
			start := i
			for i < len(runes) && runes[i] != '"' {
				value.WriteRune(runes[i])
				i++
			}
			if i == len(runes) || i == start {
				return nil, ErrInvalidSearch
			}
			i++
		}
		if value.Len() == 0 {
			return nil, ErrInvalidSearch
		}
		tokens = append(tokens, searchToken{value: value.String(), quoted: quoted})
		if len(tokens) > 128 {
			return nil, ErrInvalidSearch
		}
	}
	return tokens, nil
}

func compileSearch(query, today string) (string, []any, error) {
	day, err := time.Parse(dateLayout, today)
	if err != nil || day.Year() < 1 || day.Format(dateLayout) != today {
		return "", nil, ErrInvalidSearch
	}
	tokens, err := tokenizeSearch(query)
	if err != nil {
		return "", nil, err
	}
	p := searchParser{tokens: tokens, args: []any{today}, today: today}
	if len(tokens) == 0 {
		return "TRUE", p.args, nil
	}
	sql, err := p.or()
	if err != nil || p.index != len(tokens) {
		return "", nil, ErrInvalidSearch
	}
	return sql, p.args, nil
}

func (p *searchParser) next(value string) bool {
	if p.index < len(p.tokens) && !p.tokens[p.index].quoted && p.tokens[p.index].value == value {
		p.index++
		return true
	}
	return false
}

func (p *searchParser) or() (string, error) {
	left, err := p.and()
	for err == nil && p.next("|") {
		var right string
		right, err = p.and()
		left = "(" + left + " OR " + right + ")"
	}
	return left, err
}

func (p *searchParser) and() (string, error) {
	left, err := p.unary()
	for err == nil && p.index < len(p.tokens) {
		if !p.tokens[p.index].quoted && (p.tokens[p.index].value == ")" || p.tokens[p.index].value == "|") {
			break
		}
		p.next("&")
		var right string
		right, err = p.unary()
		left = "(" + left + " AND " + right + ")"
	}
	return left, err
}

func (p *searchParser) unary() (string, error) {
	p.depth++
	defer func() { p.depth-- }()
	if p.depth > 32 {
		return "", ErrInvalidSearch
	}
	if p.next("!") {
		sql, err := p.unary()
		return "(NOT (" + sql + "))", err
	}
	if p.next("(") {
		sql, err := p.or()
		if err != nil || !p.next(")") {
			return "", ErrInvalidSearch
		}
		return "(" + sql + ")", nil
	}
	if p.index >= len(p.tokens) {
		return "", ErrInvalidSearch
	}
	token := p.tokens[p.index]
	p.index++
	if !token.quoted && strings.ContainsAny(token.value, "&|!()") {
		return "", ErrInvalidSearch
	}
	return p.atom(token)
}

func (p *searchParser) bind(value any) string {
	p.args = append(p.args, value)
	// $1 is always the owner, $2 is today.
	return fmt.Sprintf("$%d", len(p.args)+1)
}

func (p *searchParser) atom(token searchToken) (string, error) {
	value := token.value
	key := normalizeSearch(value)
	if !token.quoted {
		if (key == "no" || key == "بدون") && p.index < len(p.tokens) {
			expected := "date"
			if key == "بدون" {
				expected = "تاریخ"
			}
			if normalizeSearch(p.tokens[p.index].value) == expected {
				p.index++
				key = "nodate"
			}
		}
		if (key == "7" || key == "۷") && p.index < len(p.tokens) && normalizeSearch(p.tokens[p.index].value) == "days" {
			p.index++
			key = "7days"
		}
		switch key {
		case "today", "امروز":
			return "due_date=$2::date", nil
		case "overdue", "دیرشده", "عقب‌افتاده", "عقبافتاده":
			return "due_date<$2::date", nil
		case "nodate", "بی‌تاریخ", "بیتاریخ":
			return "due_date IS NULL", nil
		case "7days", "۷روز", "7روز":
			return "due_date BETWEEN $2::date AND $2::date+6", nil
		case "all", "همه":
			return "TRUE", nil
		}
		if len(key) == 2 && key[0] == 'p' && key[1] >= '1' && key[1] <= '4' {
			return "priority=" + p.bind(int(key[1]-'0')), nil
		}
	}
	if strings.HasPrefix(value, "##") {
		name := normalizeSearch(strings.TrimPrefix(value, "##"))
		if name == "" {
			return "", ErrInvalidSearch
		}
		arg := p.bind(name)
		return "project_id IN (WITH RECURSIVE descendants AS (SELECT id FROM projects WHERE owner_id=$1 AND (" + normalizedSQL("name") + "=" + arg + " OR id=" + arg + ") UNION SELECT p.id FROM projects p JOIN descendants d ON p.parent_id=d.id WHERE p.owner_id=$1) SELECT id FROM descendants)", nil
	}
	if strings.HasPrefix(value, "#") {
		name := normalizeSearch(strings.TrimPrefix(value, "#"))
		if name == "" {
			return "", ErrInvalidSearch
		}
		arg := p.bind(name)
		return "project_id IN (SELECT id FROM projects WHERE owner_id=$1 AND (" + normalizedSQL("name") + "=" + arg + " OR id=" + arg + "))", nil
	}
	if strings.HasPrefix(value, "@") {
		name := normalizeSearch(strings.TrimPrefix(value, "@"))
		if name == "" {
			return "", ErrInvalidSearch
		}
		arg := p.bind(name)
		return "id IN (SELECT tl.task_id FROM task_labels tl JOIN labels l ON l.owner_id=tl.owner_id AND l.id=tl.label_id WHERE tl.owner_id=$1 AND (" + normalizedSQL("l.name") + "=" + arg + " OR l.id=" + arg + "))", nil
	}
	if !token.quoted && (strings.Contains(value, ":") || strings.HasPrefix(key, "p") && len(key) == 2 && key[1] >= '0' && key[1] <= '9') {
		return "", ErrInvalidSearch
	}
	if key == "" {
		return "", ErrInvalidSearch
	}
	arg := p.bind(key)
	return "(strpos(" + normalizedSQL("title") + "," + arg + ")>0 OR strpos(" + normalizedSQL("description") + "," + arg + ")>0)", nil
}

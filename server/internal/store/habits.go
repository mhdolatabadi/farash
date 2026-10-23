package store

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"math"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

var (
	ErrHabitNotFound        = errors.New("habit not found")
	ErrInvalidHabit         = errors.New("invalid habit")
	ErrInvalidEntry         = errors.New("invalid habit entry")
	ErrHabitLimit           = errors.New("too many habits")
	ErrHabitRequestConflict = errors.New("habit request conflict")
)

// MaxHabits caps habits per account, archived ones included.
const MaxHabits = 200

// habitHistoryDays bounds the entries returned with each habit; older scores
// have decayed to almost nothing by then.
const habitHistoryDays = 5 * 366

type HabitEntry struct {
	Day   string  `json:"day"`
	Value float64 `json:"value"`
	Skip  bool    `json:"skip"`
}

type Habit struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Question    string       `json:"question"`
	Notes       string       `json:"notes"`
	Color       int          `json:"color"`
	Kind        string       `json:"kind"`
	FreqNum     int          `json:"freq_num"`
	FreqDen     int          `json:"freq_den"`
	TargetType  string       `json:"target_type"`
	TargetValue float64      `json:"target_value"`
	Unit        string       `json:"unit"`
	SortOrder   int          `json:"sort_order"`
	Archived    bool         `json:"archived"`
	CreatedAt   time.Time    `json:"created_at"`
	Entries     []HabitEntry `json:"entries"`
}

// HabitInput creates a habit, or changes the fields that are set.
type HabitInput struct {
	RequestKey  string   `json:"request_key,omitempty"`
	Name        *string  `json:"name"`
	Question    *string  `json:"question"`
	Notes       *string  `json:"notes"`
	Color       *int     `json:"color"`
	Kind        *string  `json:"kind"`
	FreqNum     *int     `json:"freq_num"`
	FreqDen     *int     `json:"freq_den"`
	TargetType  *string  `json:"target_type"`
	TargetValue *float64 `json:"target_value"`
	Unit        *string  `json:"unit"`
	SortOrder   *int     `json:"sort_order"`
	Archived    *bool    `json:"archived"`
}

type HabitEntryInput struct {
	Value float64 `json:"value"`
	Skip  bool    `json:"skip"`
}

const habitColumns = `id, name, question, notes, color, kind, freq_num, freq_den, target_type, target_value, unit, sort_order, archived_at IS NOT NULL, created_at`

func scanHabit(row pgx.Row) (Habit, error) {
	var h Habit
	err := row.Scan(&h.ID, &h.Name, &h.Question, &h.Notes, &h.Color, &h.Kind, &h.FreqNum, &h.FreqDen, &h.TargetType, &h.TargetValue, &h.Unit, &h.SortOrder, &h.Archived, &h.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrHabitNotFound
	}
	h.Entries = []HabitEntry{}
	return h, err
}

// apply merges the set fields of in into h and validates the result.
func (in HabitInput) apply(h *Habit) error {
	if in.Name != nil {
		h.Name = strings.TrimSpace(*in.Name)
	}
	if in.Question != nil {
		h.Question = strings.TrimSpace(*in.Question)
	}
	if in.Notes != nil {
		h.Notes = strings.TrimSpace(*in.Notes)
	}
	if in.Color != nil {
		h.Color = *in.Color
	}
	if in.Kind != nil {
		h.Kind = *in.Kind
	}
	if in.FreqNum != nil {
		h.FreqNum = *in.FreqNum
	}
	if in.FreqDen != nil {
		h.FreqDen = *in.FreqDen
	}
	if in.TargetType != nil {
		h.TargetType = *in.TargetType
	}
	if in.TargetValue != nil {
		h.TargetValue = *in.TargetValue
	}
	if in.Unit != nil {
		h.Unit = strings.TrimSpace(*in.Unit)
	}
	if in.SortOrder != nil {
		h.SortOrder = *in.SortOrder
	}
	if in.Archived != nil {
		h.Archived = *in.Archived
	}
	switch {
	case h.Name == "" || utf8.RuneCountInString(h.Name) > 200,
		utf8.RuneCountInString(h.Question) > 300,
		utf8.RuneCountInString(h.Notes) > 2000,
		utf8.RuneCountInString(h.Unit) > 40,
		h.Color < 0 || h.Color > 19,
		h.Kind != "boolean" && h.Kind != "numeric",
		h.TargetType != "at_least" && h.TargetType != "at_most",
		h.FreqDen < 1 || h.FreqDen > 365 || h.FreqNum < 1 || h.FreqNum > h.FreqDen,
		math.IsNaN(h.TargetValue) || math.IsInf(h.TargetValue, 0) || h.TargetValue < 0 || h.TargetValue > 1e9,
		h.Kind == "numeric" && h.TargetValue == 0 && h.TargetType == "at_least":
		return ErrInvalidHabit
	}
	return nil
}

// ParseHabitDay reads a YYYY-MM-DD day, rejecting days after tomorrow (UTC),
// which leaves room for every time zone's today.
func ParseHabitDay(day string, now time.Time) (time.Time, error) {
	d, err := time.Parse(time.DateOnly, day)
	if err != nil || d.Year() < 2000 || d.After(now.UTC().AddDate(0, 0, 1)) {
		return time.Time{}, ErrInvalidEntry
	}
	return d, nil
}

func (s *Store) ListHabits(ctx context.Context, owner string) ([]Habit, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+habitColumns+` FROM habits WHERE owner_id=$1 ORDER BY sort_order, created_at, id`, owner)
	if err != nil {
		return nil, err
	}
	habits := []Habit{}
	index := map[string]int{}
	for rows.Next() {
		h, err := scanHabit(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		index[h.ID] = len(habits)
		habits = append(habits, h)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows, err = s.pool.Query(ctx, `SELECT habit_id, to_char(day,'YYYY-MM-DD'), value, skip FROM habit_entries
		WHERE owner_id=$1 AND day >= current_date - $2::int ORDER BY habit_id, day`, owner, habitHistoryDays)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var e HabitEntry
		if err := rows.Scan(&id, &e.Day, &e.Value, &e.Skip); err != nil {
			return nil, err
		}
		if i, ok := index[id]; ok {
			habits[i].Entries = append(habits[i].Entries, e)
		}
	}
	return habits, rows.Err()
}

var habitRequestKey = regexp.MustCompile(`^[A-Za-z0-9_-]{16,128}$`)

func (s *Store) CreateHabit(ctx context.Context, owner string, in HabitInput) (Habit, error) {
	if in.RequestKey != "" && !habitRequestKey.MatchString(in.RequestKey) {
		return Habit{}, ErrInvalidHabit
	}
	h := Habit{Color: 8, Kind: "boolean", FreqNum: 1, FreqDen: 1, TargetType: "at_least"}
	in.Archived = nil
	if err := in.apply(&h); err != nil {
		return Habit{}, err
	}
	if h.Kind == "boolean" {
		h.TargetValue, h.Unit = 0, ""
	}
	canonical, _ := json.Marshal(struct {
		Habit        Habit
		ExplicitSort bool
	}{h, in.SortOrder != nil})
	fingerprint := sha256.Sum256(canonical)
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Habit{}, err
	}
	defer tx.Rollback(ctx)
	// Serialize creates so the count limit holds across devices.
	if _, err = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); err != nil {
		return Habit{}, err
	}
	if in.RequestKey != "" {
		var previousHash []byte
		var response []byte
		err = tx.QueryRow(ctx, `SELECT payload_hash, response FROM habit_create_requests WHERE owner_id=$1 AND request_key=$2`, owner, in.RequestKey).Scan(&previousHash, &response)
		if err == nil {
			if string(previousHash) != string(fingerprint[:]) {
				return Habit{}, ErrHabitRequestConflict
			}
			var previous Habit
			if err = json.Unmarshal(response, &previous); err != nil {
				return Habit{}, err
			}
			return previous, tx.Commit(ctx)
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return Habit{}, err
		}
	}
	if in.RequestKey != "" {
		var requests int
		if err = tx.QueryRow(ctx, `SELECT count(*) FROM habit_create_requests WHERE owner_id=$1`, owner).Scan(&requests); err != nil {
			return Habit{}, err
		}
		if requests >= 10000 {
			return Habit{}, ErrHabitLimit
		}
	}
	var count, next int
	if err = tx.QueryRow(ctx, `SELECT count(*), COALESCE(max(sort_order)+1,0) FROM habits WHERE owner_id=$1`, owner).Scan(&count, &next); err != nil {
		return Habit{}, err
	}
	if count >= MaxHabits {
		return Habit{}, ErrHabitLimit
	}
	if in.SortOrder == nil {
		h.SortOrder = next
	}
	created, err := scanHabit(tx.QueryRow(ctx, `INSERT INTO habits(id,owner_id,name,question,notes,color,kind,freq_num,freq_den,target_type,target_value,unit,sort_order)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING `+habitColumns,
		newID(), owner, h.Name, h.Question, h.Notes, h.Color, h.Kind, h.FreqNum, h.FreqDen, h.TargetType, h.TargetValue, h.Unit, h.SortOrder))
	if err != nil {
		return Habit{}, err
	}
	if in.RequestKey != "" {
		response, err := json.Marshal(created)
		if err != nil {
			return Habit{}, err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO habit_create_requests(owner_id, request_key, payload_hash, response) VALUES($1,$2,$3,$4)`, owner, in.RequestKey, fingerprint[:], response); err != nil {
			return Habit{}, err
		}
	}
	return created, tx.Commit(ctx)
}

func (s *Store) getHabit(ctx context.Context, q pgx.Tx, owner, id string) (Habit, error) {
	h, err := scanHabit(q.QueryRow(ctx, `SELECT `+habitColumns+` FROM habits WHERE owner_id=$1 AND id=$2 FOR UPDATE`, owner, id))
	if err != nil {
		return Habit{}, err
	}
	rows, err := q.Query(ctx, `SELECT to_char(day,'YYYY-MM-DD'), value, skip FROM habit_entries WHERE habit_id=$1 AND day >= current_date - $2::int ORDER BY day`, id, habitHistoryDays)
	if err != nil {
		return Habit{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var e HabitEntry
		if err := rows.Scan(&e.Day, &e.Value, &e.Skip); err != nil {
			return Habit{}, err
		}
		h.Entries = append(h.Entries, e)
	}
	return h, rows.Err()
}

func (s *Store) UpdateHabit(ctx context.Context, owner, id string, in HabitInput) (Habit, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Habit{}, err
	}
	defer tx.Rollback(ctx)
	h, err := s.getHabit(ctx, tx, owner, id)
	if err != nil {
		return Habit{}, err
	}
	// The kind is fixed at creation: entries mean different things per kind.
	if in.Kind != nil && *in.Kind != h.Kind {
		return Habit{}, ErrInvalidHabit
	}
	if err := in.apply(&h); err != nil {
		return Habit{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE habits SET name=$3,question=$4,notes=$5,color=$6,freq_num=$7,freq_den=$8,target_type=$9,target_value=$10,unit=$11,sort_order=$12,
		archived_at=CASE WHEN $13 THEN COALESCE(archived_at,now()) ELSE NULL END WHERE owner_id=$1 AND id=$2`,
		owner, id, h.Name, h.Question, h.Notes, h.Color, h.FreqNum, h.FreqDen, h.TargetType, h.TargetValue, h.Unit, h.SortOrder, h.Archived); err != nil {
		return Habit{}, err
	}
	h, err = s.getHabit(ctx, tx, owner, id)
	if err != nil {
		return Habit{}, err
	}
	return h, tx.Commit(ctx)
}

func (s *Store) DeleteHabit(ctx context.Context, owner, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM habits WHERE owner_id=$1 AND id=$2`, owner, id)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrHabitNotFound
	}
	return err
}

// ReorderHabits gives the listed habits consecutive positions; habits of
// another owner make the whole request not found.
func (s *Store) ReorderHabits(ctx context.Context, owner string, ids []string) error {
	if len(ids) == 0 || len(ids) > MaxHabits {
		return ErrInvalidHabit
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			return ErrInvalidHabit
		}
		seen[id] = true
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for i, id := range ids {
		tag, err := tx.Exec(ctx, `UPDATE habits SET sort_order=$3 WHERE owner_id=$1 AND id=$2`, owner, id, i)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrHabitNotFound
		}
	}
	return tx.Commit(ctx)
}

// SetHabitEntry records one day. A yes/no habit stores 1 for done and 0 for
// not done; a numeric habit stores the amount. Skip marks a day that neither
// counts nor breaks the streak.
func (s *Store) SetHabitEntry(ctx context.Context, owner, id, day string, in HabitEntryInput) (HabitEntry, error) {
	d, err := ParseHabitDay(day, time.Now())
	if err != nil {
		return HabitEntry{}, err
	}
	if math.IsNaN(in.Value) || math.IsInf(in.Value, 0) || in.Value < 0 || in.Value > 1e9 {
		return HabitEntry{}, ErrInvalidEntry
	}
	var kind string
	if err := s.pool.QueryRow(ctx, `SELECT kind FROM habits WHERE owner_id=$1 AND id=$2`, owner, id).Scan(&kind); errors.Is(err, pgx.ErrNoRows) {
		return HabitEntry{}, ErrHabitNotFound
	} else if err != nil {
		return HabitEntry{}, err
	}
	if in.Skip {
		in.Value = 0
	}
	if kind == "boolean" && in.Value != 0 && in.Value != 1 {
		return HabitEntry{}, ErrInvalidEntry
	}
	var e HabitEntry
	err = s.pool.QueryRow(ctx, `INSERT INTO habit_entries(habit_id,owner_id,day,value,skip) VALUES($1,$2,$3,$4,$5)
		ON CONFLICT (habit_id,day) DO UPDATE SET value=EXCLUDED.value, skip=EXCLUDED.skip, updated_at=now()
		RETURNING to_char(day,'YYYY-MM-DD'), value, skip`, id, owner, d, in.Value, in.Skip).Scan(&e.Day, &e.Value, &e.Skip)
	return e, err
}

// ClearHabitEntry returns a day to unknown. Clearing an unknown day succeeds.
func (s *Store) ClearHabitEntry(ctx context.Context, owner, id, day string) error {
	d, err := ParseHabitDay(day, time.Now())
	if err != nil {
		return err
	}
	var exists bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM habits WHERE owner_id=$1 AND id=$2)`, owner, id).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrHabitNotFound
	}
	_, err = s.pool.Exec(ctx, `DELETE FROM habit_entries WHERE owner_id=$1 AND habit_id=$2 AND day=$3`, owner, id, d)
	return err
}

package store

import (
	"errors"
	"strings"
	"testing"
)

func TestSyncCursorRejectsOversizedInput(t *testing.T) {
	owner := "550e8400-e29b-41d4-a716-446655440000"
	valid := syncCursor(owner, 42)
	if len(valid) > 128 {
		t.Fatal("valid cursor unexpectedly exceeds limit")
	}
	if revision, err := parseSyncCursor(owner, valid); err != nil || revision != 42 {
		t.Fatalf("valid cursor: revision=%d err=%v", revision, err)
	}
	for _, cursor := range []string{
		valid + strings.Repeat("x", 129),
		strings.Repeat("a", 1024*1024),
	} {
		if _, err := parseSyncCursor(owner, cursor); !errors.Is(err, ErrInvalidSync) {
			t.Fatalf("oversized cursor length %d: %v", len(cursor), err)
		}
	}
}

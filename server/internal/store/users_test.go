package store

import (
	"context"
	"errors"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestUsers(t *testing.T) {
	pool := testPool(t)
	store := New(pool)
	ctx := context.Background()

	hash, err := bcrypt.GenerateFromPassword([]byte("long-enough"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatal(err)
	}
	created, err := store.CreateUser(ctx, " USER@example.COM ", string(hash))
	if err != nil {
		t.Fatal(err)
	}
	if created.Email != "user@example.com" {
		t.Fatalf("email = %q", created.Email)
	}

	if _, err := store.CreateUser(ctx, "user@example.com", string(hash)); !errors.Is(err, ErrEmailTaken) {
		t.Fatalf("duplicate error = %v", err)
	}

	byEmail, err := store.UserByEmail(ctx, "USER@example.com")
	if err != nil {
		t.Fatal(err)
	}
	if byEmail.ID != created.ID {
		t.Fatalf("by email id = %q, want %q", byEmail.ID, created.ID)
	}

	byID, err := store.UserByID(ctx, created.ID)
	if err != nil {
		t.Fatal(err)
	}
	if byID.Email != created.Email {
		t.Fatalf("by id email = %q", byID.Email)
	}
}

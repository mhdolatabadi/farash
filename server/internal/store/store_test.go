package store

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// testPool connects to TEST_DATABASE_URL, drops every table and applies the
// migrations. Point it at a disposable database.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if _, err := pool.Exec(ctx, `DROP SCHEMA public CASCADE; CREATE SCHEMA public`); err != nil {
		t.Fatal(err)
	}
	if err := Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	return pool
}

func TestMigrateIsIdempotent(t *testing.T) {
	pool := testPool(t)
	if err := Migrate(context.Background(), pool); err != nil {
		t.Fatalf("second run: %v", err)
	}
	var applied int
	if err := pool.QueryRow(context.Background(),
		"SELECT count(*) FROM schema_migrations").Scan(&applied); err != nil {
		t.Fatal(err)
	}
	if applied == 0 {
		t.Fatal("no migrations recorded")
	}
}

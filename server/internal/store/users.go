package store

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrEmailTaken        = errors.New("email already registered")
	ErrInvalidCredential = errors.New("invalid credentials")
	ErrUserNotFound      = errors.New("user not found")
)

type Store struct {
	pool *pgxpool.Pool
}

type User struct {
	ID           string
	Email        string
	PasswordHash string
}

func New(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func NormalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func (s *Store) CreateUser(ctx context.Context, email string, passwordHash string) (User, error) {
	user := User{
		ID:           newID(),
		Email:        NormalizeEmail(email),
		PasswordHash: passwordHash,
	}
	// The account and its Inbox are created together, so no account ever
	// exists without an Inbox.
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			INSERT INTO users (id, email, password_hash)
			VALUES ($1, $2, $3)
		`, user.ID, user.Email, user.PasswordHash); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO projects (id, owner_id, name, is_inbox)
			VALUES ($1, $2, $3, true)
		`, newID(), user.ID, InboxName)
		return err
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return User{}, ErrEmailTaken
		}
		return User{}, err
	}
	return user, nil
}

func (s *Store) UserByEmail(ctx context.Context, email string) (User, error) {
	return s.userBy(ctx, "email", NormalizeEmail(email))
}

func (s *Store) UserByID(ctx context.Context, id string) (User, error) {
	return s.userBy(ctx, "id", id)
}

func (s *Store) userBy(ctx context.Context, column string, value string) (User, error) {
	query := `SELECT id, email, password_hash FROM users WHERE ` + column + ` = $1`
	var user User
	if err := s.pool.QueryRow(ctx, query, value).Scan(&user.ID, &user.Email, &user.PasswordHash); err != nil {
		return User{}, ErrUserNotFound
	}
	return user, nil
}

func newID() string {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(bytes[:])
}

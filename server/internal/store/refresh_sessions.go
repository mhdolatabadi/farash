package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

var ErrRefreshInvalid = errors.New("invalid refresh token")

// CreateRefreshSession persists only the digest of an opaque refresh token.
func (s *Store) CreateRefreshSession(ctx context.Context, userID, digest string, expires time.Time) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO auth_refresh_sessions (token_hash, user_id, expires_at)
		VALUES ($1, $2, $3)`, digest, userID, expires)
	return err
}

// RotateRefreshSession atomically consumes an old token and creates its replacement.
// Concurrent refresh attempts cannot both succeed, preventing token replay.
func (s *Store) RotateRefreshSession(ctx context.Context, oldDigest, newDigest string, expires time.Time) (string, error) {
	var userID string
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `UPDATE auth_refresh_sessions
			SET revoked_at = now()
			WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
			RETURNING user_id`, oldDigest).Scan(&userID)
		if err != nil {
			return ErrRefreshInvalid
		}
		_, err = tx.Exec(ctx, `INSERT INTO auth_refresh_sessions (token_hash, user_id, expires_at)
			VALUES ($1, $2, $3)`, newDigest, userID, expires)
		return err
	})
	if err != nil {
		return "", err
	}
	return userID, nil
}

func (s *Store) RevokeRefreshSession(ctx context.Context, digest string) error {
	_, err := s.pool.Exec(ctx, `UPDATE auth_refresh_sessions
		SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL`, digest)
	return err
}

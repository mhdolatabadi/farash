package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/farash/server/internal/httpapi"
	"github.com/mhdolatabadi/farash/server/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("Farash API failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		return errors.New("DATABASE_URL is required")
	}
	authSecret := os.Getenv("AUTH_JWT_SECRET")
	if authSecret == "" {
		return errors.New("AUTH_JWT_SECRET is required")
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer pool.Close()
	if err := store.Migrate(ctx, pool); err != nil {
		return fmt.Errorf("migrate database: %w", err)
	}

	server := &http.Server{
		Addr: ":" + port,
		Handler: httpapi.NewHandler(httpapi.Config{
			AllowedOrigin: os.Getenv("WEB_ORIGIN"),
			Ping:          pool.Ping,
			Store:         store.New(pool),
			AuthSecret:    []byte(authSecret),
			AuthTokenTTL:  authTokenTTL(),
		}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		slog.Info("Farash API started", "address", server.Addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	select {
	case err := <-serverErr:
		return err
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}
	slog.Info("Farash API stopped")
	return nil
}

func authTokenTTL() time.Duration {
	hours, err := strconv.Atoi(os.Getenv("AUTH_TOKEN_TTL_HOURS"))
	if err != nil || hours <= 0 {
		return 24 * time.Hour
	}
	return time.Duration(hours) * time.Hour
}

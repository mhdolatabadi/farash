package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type searchStore interface {
	SearchTasks(context.Context, string, store.SearchOptions) (store.SearchPage, error)
	ListSavedFilters(context.Context, string) ([]store.SavedFilter, error)
	SaveFilter(context.Context, string, string, store.SavedFilterInput) (store.SavedFilter, error)
	DeleteSavedFilter(context.Context, string, string) error
}

func searchRoutes(mux *http.ServeMux, auth *authHandler, data searchStore) {
	handler := func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		if r.URL.Path == "/api/v1/search" {
			q := r.URL.Query()
			input := store.SearchOptions{Query: q.Get("q"), Today: q.Get("today"), Sort: q.Get("sort")}
			if raw := q.Get("completed"); raw != "" {
				if raw != "true" && raw != "false" {
					writeError(w, http.StatusBadRequest, "invalid_search")
					return
				}
				input.ShowCompleted = raw == "true"
			}
			for _, value := range []struct {
				key    string
				target *int
			}{{"limit", &input.Limit}, {"offset", &input.Offset}} {
				if raw := q.Get(value.key); raw != "" {
					n, err := strconv.Atoi(raw)
					if err != nil {
						writeError(w, http.StatusBadRequest, "invalid_search")
						return
					}
					*value.target = n
				}
			}
			page, err := data.SearchTasks(r.Context(), user.ID, input)
			if err != nil {
				writeSearchError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, page)
			return
		}
		id := r.PathValue("id")
		switch r.Method {
		case http.MethodGet:
			filters, err := data.ListSavedFilters(r.Context(), user.ID)
			if err != nil {
				writeSearchError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string][]store.SavedFilter{"filters": filters})
		case http.MethodDelete:
			if err := data.DeleteSavedFilter(r.Context(), user.ID, id); err != nil {
				writeSearchError(w, err)
				return
			}
			w.WriteHeader(http.StatusNoContent)
		default:
			input, ok := decodeTaskRequest[store.SavedFilterInput](w, r)
			if !ok {
				return
			}
			filter, err := data.SaveFilter(r.Context(), user.ID, id, input)
			if err != nil {
				writeSearchError(w, err)
				return
			}
			status := http.StatusOK
			if r.Method == http.MethodPost {
				status = http.StatusCreated
			}
			writeJSON(w, status, map[string]store.SavedFilter{"filter": filter})
		}
	}
	mux.HandleFunc("GET /api/v1/search", handler)
	mux.HandleFunc("GET /api/v1/filters", handler)
	mux.HandleFunc("POST /api/v1/filters", handler)
	mux.HandleFunc("PUT /api/v1/filters/{id}", handler)
	mux.HandleFunc("DELETE /api/v1/filters/{id}", handler)
}

func writeSearchError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrInvalidSearch), errors.Is(err, store.ErrInvalidFilter):
		writeError(w, http.StatusBadRequest, "invalid_search")
	case errors.Is(err, store.ErrFilterNotFound):
		writeError(w, http.StatusNotFound, "filter_not_found")
	default:
		writeError(w, http.StatusInternalServerError, "search_failed")
	}
}

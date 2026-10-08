package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type tasksStore interface {
	ListTasks(context.Context, string, string, bool) ([]store.Task, error)
	ListDueTasks(context.Context, string, string, string) ([]store.Task, error)
	CreateTask(context.Context, string, store.TaskInput) (store.Task, error)
	UpdateTask(context.Context, string, string, store.TaskUpdate) (store.Task, error)
	CompleteTask(context.Context, string, string, bool) (store.Task, error)
	DeleteTask(context.Context, string, string) error
	RestoreTask(context.Context, string, string) (store.Task, error)
	ReorderTasks(context.Context, string, string, []string) error
	RescheduleTasks(context.Context, string, []string, *store.DueInput) ([]store.Task, error)
}

type tasksHandler struct {
	auth *authHandler
	data tasksStore
}

func (h *tasksHandler) handle(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	owner, id := user.ID, r.PathValue("id")
	var task store.Task
	var err error
	switch {
	case r.Method == http.MethodGet:
		query := r.URL.Query()
		project := query.Get("projectId")
		if project == "" && query.Has("to") {
			// Due views across projects: the client sends its own today.
			tasks, err := h.data.ListDueTasks(r.Context(), owner, query.Get("from"), query.Get("to"))
			if err != nil {
				writeTaskError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string][]store.Task{"tasks": tasks})
			return
		}
		if project == "" {
			writeError(w, http.StatusBadRequest, "project_id_required")
			return
		}
		completed := r.URL.Query().Get("showCompleted")
		if completed != "" && completed != "true" && completed != "false" {
			writeError(w, http.StatusBadRequest, "invalid_show_completed")
			return
		}
		tasks, err := h.data.ListTasks(r.Context(), owner, project, completed == "true")
		if err != nil {
			writeTaskError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string][]store.Task{"tasks": tasks})
		return
	case r.Method == http.MethodDelete:
		if err := h.data.DeleteTask(r.Context(), owner, id); err != nil {
			writeTaskError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	case r.Method == http.MethodPatch:
		input, ok := decodeTaskRequest[store.TaskUpdate](w, r)
		if !ok {
			return
		}
		task, err = h.data.UpdateTask(r.Context(), owner, id, input)
	case r.URL.Path == "/api/v1/tasks/reorder":
		input, ok := decodeTaskRequest[struct {
			ProjectID string   `json:"project_id"`
			TaskIDs   []string `json:"task_ids"`
		}](w, r)
		if !ok {
			return
		}
		if input.ProjectID == "" {
			writeError(w, http.StatusBadRequest, "project_id_required")
			return
		}
		if err := h.data.ReorderTasks(r.Context(), owner, input.ProjectID, input.TaskIDs); err != nil {
			writeTaskError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		return
	case r.URL.Path == "/api/v1/tasks/reschedule":
		input, ok := decodeTaskRequest[struct {
			TaskIDs []string        `json:"task_ids"`
			Due     *store.DueInput `json:"due"`
		}](w, r)
		if !ok {
			return
		}
		tasks, err := h.data.RescheduleTasks(r.Context(), owner, input.TaskIDs, input.Due)
		if err != nil {
			writeTaskError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string][]store.Task{"tasks": tasks})
		return
	case id != "":
		switch r.PathValue("action") {
		case "close":
			task, err = h.data.CompleteTask(r.Context(), owner, id, true)
		case "reopen":
			task, err = h.data.CompleteTask(r.Context(), owner, id, false)
		case "restore":
			task, err = h.data.RestoreTask(r.Context(), owner, id)
		default:
			writeError(w, http.StatusNotFound, "not_found")
			return
		}
	default:
		input, ok := decodeTaskRequest[store.TaskInput](w, r)
		if !ok {
			return
		}
		task, err = h.data.CreateTask(r.Context(), owner, input)
	}
	if err != nil {
		writeTaskError(w, err)
		return
	}
	status := http.StatusOK
	if r.Method == http.MethodPost && id == "" {
		status = http.StatusCreated
	}
	writeJSON(w, status, map[string]store.Task{"task": task})
}

func decodeTaskRequest[T any](w http.ResponseWriter, r *http.Request) (T, bool) {
	var input T
	defer r.Body.Close()
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 128*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return input, false
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return input, false
	}
	return input, true
}

func writeTaskError(w http.ResponseWriter, err error) {
	if writeSectionError(w, err) {
		return
	}
	switch {
	case errors.Is(err, store.ErrTaskNotFound):
		writeError(w, http.StatusNotFound, "task_not_found")
	case errors.Is(err, store.ErrTaskProject):
		writeError(w, http.StatusNotFound, "project_not_found")
	case errors.Is(err, store.ErrInvalidTask):
		writeError(w, http.StatusBadRequest, "invalid_task")
	case errors.Is(err, store.ErrParentNotFound):
		writeError(w, http.StatusNotFound, "parent_not_found")
	case errors.Is(err, store.ErrInvalidParent):
		writeError(w, http.StatusBadRequest, "invalid_parent")
	case errors.Is(err, store.ErrInvalidDue):
		writeError(w, http.StatusBadRequest, "invalid_due")
	case errors.Is(err, store.ErrInvalidDeadline):
		writeError(w, http.StatusBadRequest, "invalid_deadline")
	case errors.Is(err, store.ErrInvalidDuration):
		writeError(w, http.StatusBadRequest, "invalid_duration")
	case errors.Is(err, store.ErrInvalidDueRange):
		writeError(w, http.StatusBadRequest, "invalid_due_range")
	case errors.Is(err, store.ErrTaskIDs):
		writeError(w, http.StatusBadRequest, "invalid_task_ids")
	case errors.Is(err, store.ErrTaskOrder):
		writeError(w, http.StatusBadRequest, "invalid_task_order")
	default:
		writeError(w, http.StatusInternalServerError, "task_write_failed")
	}
}

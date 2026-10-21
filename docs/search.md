# Search and saved filters (#13)

Search is owner-scoped and reads live tasks in active projects. Deleted tasks are excluded; completed tasks are opt-in. Shared objects and comments are not silently included until their authorization/data contracts are implemented. Unsupported field syntax (including assigned:me) returns invalid_search rather than fabricated results.

GET /api/v1/search accepts q, required today (Gregorian civil YYYY-MM-DD from the user's calendar/timezone), completed=true|false, sort=due|priority|title|project, limit (default100/max200), offset (max100000). Results contain tasks and has_more. Current pagination is offset-based, not a snapshot: changes between requests can shift later pages.

The query language supports literal text in titles/descriptions, double-quoted phrases, today/امروز, overdue/دیرشده, no date/بدون تاریخ/بی‌تاریخ, 7 days/۷روز, p1..p4, #project, ##project-with-descendants and @label. Names with spaces can be quoted after their prefix. IDs are accepted alongside names; duplicate names match all owned objects. & and whitespace mean AND; | means OR; ! means NOT; parentheses override precedence. A quoted bare keyword searches its text. Priority, due-date and project sorting are deterministic.

Persian ي/ى/ك map to ی/ی/ک, case is folded, and whitespace/half-spaces are ignored. Text matching is literal substring search, with values bound to PostgreSQL parameters; wildcard characters do not become patterns. This is normalized search rather than linguistic stemming. The query is bounded to1000runes/128tokens/32nesting levels.

GET/POST /api/v1/filters list/create; PUT/DELETE /api/v1/filters/{id} replace/delete. Filters store name, query, color, favorite and sort; dates remain relative when evaluated later. No filter can access data beyond the caller's scope. Migration015 is additive; rollback can retain saved_filters.

This delivery does not yet establish full #13 acceptance: comment search, shared/assigned predicates, a form-based smart-list builder, grouping and the client entry point remain separate follow-through until explicitly implemented and verified. Do not close #13 based on backend delivery alone.

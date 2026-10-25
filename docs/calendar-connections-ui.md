# Connected calendar settings

Refs #119. The account menu opens **اتصال تقویم‌ها**. This client requires the
calendar connection API; merge it with the server implementation before rollout.

- A server without Google configuration explains that setup is unavailable and
  does not offer an enabled connect action.
- **آماده‌سازی اتصال Google** requests an authorization ticket. The separate
  **باز کردن Google** action opens the browser directly from a user gesture, so
  Web popup policies do not turn an awaited API call into a blocked popup.
- Google consent stays in the system browser. Android uses `ACTION_VIEW`; this
  slice does not register App Links or claim automatic Android handoff. The
  configured HTTPS return URL must render a usable return page. The user returns
  to the app; resume refreshes status after browser launch, and the refresh action
  is always available. Web users return to the original tab and refresh status.
- Select at most 20 calendars and save the versioned selection. The seven-day
  event list is read-only, with previous/next windows. It never creates tasks or
  writes provider events, and does not claim background or incremental sync.
- Timed events use the device timezone; all-day events preserve provider dates,
  including their exclusive end date. Dates use the app's Jalali/Gregorian choice.
- Disconnect requires confirmation, stops display, and reports when provider
  revocation could not be confirmed so users can revoke in Google themselves.

Tickets and provider events are held only in this screen's memory. They are not
included in offline snapshots, URLs saved by the app, logs or export. Responses
and subsequent actions are fenced to the session which opened the screen. A
provider reauthorization error immediately clears event details and offers
reconnection. Calendar-selection conflicts ask for a reload rather than silently
replacing the other client's selection.

Unit/widget coverage includes late-session responses, one-use browser tickets,
provider reconnect errors, versioned selection, all-day events, disconnect,
configuration-disabled state, browser resume and narrow 2× dark text. CI captures
phone, dark large-text and expanded widget layouts. Real Google sandbox consent,
Android browser return, native keyboard/insets and device accessibility remain
release checks; widget captures are not hardware evidence.

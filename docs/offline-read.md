# Read-only offline resume (#113)

The production client retains a bounded convenience snapshot of successful
authenticated GET responses for identity, projects, tasks, sections and labels.
It is not a local authoritative database or a command queue. #21 remains open.

Storage uses FlutterSecureStorage under one constant key. Its value is scoped
to SHA-256 of the complete API base URI and exact access token; raw tokens are
not written into cache keys or cache data. Switching account/server/token drops
the previous snapshot. Responses are limited to 20, total encoded size 1MiB,
each response at most 512KiB and age at most seven days. Oldest responses are
evicted first. Only previously visited query variants can be viewed offline.
Expired, malformed or unreadable data is not accepted as server confirmation.

Only transport failures use cached data. HTTP 401/404/5xx do not fall back.
401 and logout clear the snapshot; generation checks prevent old inflight
responses from writing after account switches or logout. Successful mutations
invalidate all cached lists except identity, so old completion/deletion data
cannot be silently resurrected offline. The subsequent confirmed GET rebuilds
the list cache.

A saved token with a matching cached identity may pass the backend health gate
after a transport failure and resume the app without another login. The app
shows an explicit read-only banner with reconnect. Mutations reject before any
request while offline; nothing is queued or falsely reported as saved. Reconnect
requires successful health and identity requests without cache fallback, then
refreshes projects. A rejected identity clears the session.

Limits: offline capture/completion, incremental feed consumption, field conflict
resolution, reminder/widget databases, full Scrum/search/time/export caches and
background reconnect are not implemented by this slice. PWA shell installation
also remains a separate gate: this enables resumed data reads when the app shell
is already available. This cache does not extend or bypass server token expiry.

Rollback may remove the optional cache integration without database migration.
The secure cache contains private task data; logout deletes only its dedicated
key, retaining unrelated device preferences. Physical device storage and offline
PWA restart behavior require separate native/browser evidence.

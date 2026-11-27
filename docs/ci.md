# Quality checks

The workflow keeps the required `flutter`, `android-ui-review`, `api`,
`deployment-config`, and `release-config` check names.

- PR pushes cancel superseded runs of that PR. Main runs finish so deployment
  and signed-release workflows can consume successful checks for the exact SHA.
- Flutter tests/analysis, web release compilation, and Android compilation run
  independently. Gradle dependencies and build state are cached; fork PRs read
  the cache without writing it.
- The installable debug APK and offline review APK remain distinct artifacts.
  The review APK is built once, then downloaded by three independent emulator
  jobs (`core`, `planning`, `account`). Together they capture all 58 existing
  screenshots, including RTL, 320px width, both themes, keyboard, and 2x text.
- Client checks are omitted only for known unrelated PR paths (server,
  documentation and server deployment). Test-only PRs run all Flutter tests and
  both builds but omit native screenshot recording. Unknown paths, workflow
  changes and client dependencies trigger the complete client checks.
- Every main push and manual run performs the full suite. Required gate jobs
  explicitly reject failures, cancellations and unexpected skips.

For native review, download all three `menval-android-ui-review-*` artifacts.
To run a group locally, use `MENVAL_CAPTURE_GROUP=core python3 tool/capture_android.py` with an emulator and the offline fixture APK installed
at the normal Flutter build output path. Omit the variable to run all groups.

Before this change, the successful Android review in run 45832712330 took
13m15s: fixture build 3m13s and emulator/capture 9m33s. Flutter's complete job
was 7m20s, while the Flutter tests themselves took approximately 95s. Compare
new successful runs on equivalent hosted runners; cold caches and download
failures affect timing. Sharding reduces wall time at the cost of additional
concurrent emulator runners; coverage and capture settling delays are preserved.

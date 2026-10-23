#!/usr/bin/env bash
set -euo pipefail
: "${ANDROID_HOME:?ANDROID_HOME is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${STORE_PASSWORD:?Release signing password is required}"
: "${KEY_ALIAS:?Release signing alias is required}"
build_tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
apk=build/app/outputs/flutter-apk/app-release.apk
aab=build/app/outputs/bundle/release/app-release.aab
"$build_tools/apksigner" verify --verbose --print-certs "$apk" > "$RUNNER_TEMP/apk-signature.txt"
"$build_tools/aapt" dump badging "$apk" > "$RUNNER_TEMP/apk-package.txt"
grep -q "package: name='ir.mhdolatabadi.farash'" "$RUNNER_TEMP/apk-package.txt"
if grep -q 'application-debuggable' "$RUNNER_TEMP/apk-package.txt"; then
  echo 'Debuggable APK rejected.' >&2
  exit 1
fi
keytool -exportcert -keystore "$RUNNER_TEMP/farash-release.jks" -storepass:env STORE_PASSWORD -alias "$KEY_ALIAS" > "$RUNNER_TEMP/release-cert.der"
expected="$(sha256sum "$RUNNER_TEMP/release-cert.der" | cut -d' ' -f1)"
actual="$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$RUNNER_TEMP/apk-signature.txt" | tr '[:upper:]' '[:lower:]')"
[[ "$actual" == "$expected" ]] || { echo 'Unexpected APK signing certificate.' >&2; exit 1; }
[[ "$(grep -c 'certificate SHA-256 digest:' "$RUNNER_TEMP/apk-signature.txt")" -eq 1 ]]
jarsigner -verify "$aab" > "$RUNNER_TEMP/aab-signature.txt"
grep -q 'jar verified' "$RUNNER_TEMP/aab-signature.txt"
if grep -Ei 'unsigned entries|not signed|jar is unsigned' "$RUNNER_TEMP/aab-signature.txt" > /dev/null; then
  echo 'Unsigned AAB content rejected.' >&2
  exit 1
fi
keytool -printcert -jarfile "$aab" -rfc > "$RUNNER_TEMP/aab-cert.pem"
openssl x509 -in "$RUNNER_TEMP/aab-cert.pem" -outform DER > "$RUNNER_TEMP/aab-cert.der"
[[ "$(sha256sum "$RUNNER_TEMP/aab-cert.der" | cut -d' ' -f1)" == "$expected" ]]

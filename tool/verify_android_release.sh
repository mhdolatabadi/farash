#!/usr/bin/env bash
set -euo pipefail
: "${ANDROID_HOME:?ANDROID_HOME is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${STORE_PASSWORD:?Release signing password is required}"
: "${KEY_ALIAS:?Release signing alias is required}"
: "${VERSION_NAME:?Selected release version is required}"
: "${VERSION_CODE:?Selected release build number is required}"
build_tools="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
apk=build/app/outputs/flutter-apk/app-release.apk
aab=build/app/outputs/bundle/release/app-release.aab
"$build_tools/apksigner" verify --verbose --print-certs "$apk" > "$RUNNER_TEMP/apk-signature.txt"
"$build_tools/aapt" dump badging "$apk" > "$RUNNER_TEMP/apk-package.txt"
python3 tool/android_release_metadata.py verify-apk "$RUNNER_TEMP/apk-package.txt"
if grep -q 'application-debuggable' "$RUNNER_TEMP/apk-package.txt"; then
  echo 'Debuggable APK rejected.' >&2
  exit 1
fi
keytool -exportcert -keystore "$RUNNER_TEMP/farash-release.jks" -storepass:env STORE_PASSWORD -alias "$KEY_ALIAS" > "$RUNNER_TEMP/release-cert.der"
expected="$(sha256sum "$RUNNER_TEMP/release-cert.der" | cut -d' ' -f1)"
# apksigner labels signers as "Signer #1", "V2 Signer:" or "Signer (minSdkVersion=…)" depending on
# version and scheme, so match on the digest itself. Certificate digests are public.
actual="$(sed -n 's/^.*Signer.* certificate SHA-256 digest: //p' "$RUNNER_TEMP/apk-signature.txt" | tr '[:upper:]' '[:lower:]' | sort -u)"
if [[ "$actual" != "$expected" ]]; then
  echo 'Unexpected APK signing certificate.' >&2
  echo "Keystore alias certificate SHA-256: $expected" >&2
  echo 'apksigner reported:' >&2
  grep -E 'Verified using|Number of signers|certificate (DN|SHA-256 digest)' "$RUNNER_TEMP/apk-signature.txt" >&2 || true
  exit 1
fi
jarsigner -verify "$aab" > "$RUNNER_TEMP/aab-signature.txt"
grep -q 'jar verified' "$RUNNER_TEMP/aab-signature.txt"
# Newer JDKs also warn "Entry … is signed in JarFile but is not signed in JarInputStream"
# when META-INF is not at the start of the zip, as in Gradle-built bundles. JarFile
# verification above still covers every entry, so only real unsigned-content warnings fail.
if grep -Ei 'contains unsigned entries|jar is unsigned' "$RUNNER_TEMP/aab-signature.txt" > /dev/null; then
  echo 'Unsigned AAB content rejected.' >&2
  cat "$RUNNER_TEMP/aab-signature.txt" >&2
  exit 1
fi
keytool -printcert -jarfile "$aab" -rfc > "$RUNNER_TEMP/aab-cert.pem"
openssl x509 -in "$RUNNER_TEMP/aab-cert.pem" -outform DER > "$RUNNER_TEMP/aab-cert.der"
aab_actual="$(sha256sum "$RUNNER_TEMP/aab-cert.der" | cut -d' ' -f1)"
[[ "$aab_actual" == "$expected" ]] || { echo "Unexpected AAB signing certificate: $aab_actual (expected $expected)." >&2; exit 1; }

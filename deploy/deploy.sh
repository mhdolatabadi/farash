#!/usr/bin/env sh
set -eu

required_vars="FARASH_DOMAIN FARASH_IMAGE_REPO FARASH_IMAGE_TAG POSTGRES_PASSWORD AUTH_JWT_SECRET GHCR_USERNAME GHCR_TOKEN"
for var in $required_vars; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

cat > .env <<EOF
FARASH_DOMAIN=$FARASH_DOMAIN
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
AUTH_JWT_SECRET=$AUTH_JWT_SECRET
AUTH_TOKEN_TTL_HOURS=${AUTH_TOKEN_TTL_HOURS:-24}
FARASH_IMAGE_REPO=$FARASH_IMAGE_REPO
FARASH_IMAGE_TAG=$FARASH_IMAGE_TAG
EOF

printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin

docker compose pull api web
docker compose up -d --remove-orphans

docker compose exec -T api /usr/local/bin/farash-api --help >/dev/null 2>&1 || true

echo "Farash deploy finished for https://$FARASH_DOMAIN"

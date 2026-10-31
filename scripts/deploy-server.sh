#!/usr/bin/env bash
set -eu

DEPLOY_REF="${DEPLOY_REF:?Missing deployment reference}"
case "$DEPLOY_REF" in
  *[!A-Za-z0-9._-]*) echo "Invalid deployment reference" >&2; exit 1 ;;
esac

docker build \
  --file /opt/smart-mobility/backend.deploy.Dockerfile \
  --tag "smr-backend:${DEPLOY_REF}" \
  /opt/smart-mobility/backend

for service in web worker beat; do
  docker tag "smr-backend:${DEPLOY_REF}" "malawi-${service}"
done

compose_file=/opt/smart-mobility/docker-compose.deploy.yml
compose_override=/opt/smart-mobility/backend/docker-compose.production.override.yml
docker compose --project-name malawi --file "$compose_file" --file "$compose_override" run --rm --no-deps \
  web python manage.py test users.tests --verbosity 1 </dev/null

backup_dir=/opt/smart-mobility/backups/backend-deploy
install -d -m 700 "$backup_dir"
backup_file="${backup_dir}/database-${DEPLOY_REF}-$(date -u +%Y%m%d%H%M%S).dump"
docker exec malawi-db-1 sh -c \
  'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" -Fc' > "$backup_file"
chmod 600 "$backup_file"
test -s "$backup_file"

docker compose --project-name malawi --file "$compose_file" --file "$compose_override" run --rm --no-deps \
  web python manage.py migrate --noinput </dev/null
docker compose --project-name malawi --file "$compose_file" --file "$compose_override" \
  up -d --no-build --no-deps --force-recreate \
  web worker beat

status=000
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --max-time 10 https://smartmobilityroadcare.com/api/auth/admin/audit-logs/ || true)"
  case "$status" in
    2??|3??|401|403|405) echo "Backend deployed; API responded with HTTP ${status}."; exit 0 ;;
  esac
  sleep 3
done
echo "Backend health check failed with HTTP ${status}." >&2
exit 1

# Backend and mobile-project deployment

This repository contains the Django API and the Rider and Roadie Flutter
applications. The production web API is deployed to the existing host at
`201.79.45.60`; publishing backend code does **not** publish new mobile app
builds to Google Play or the App Store.

The production layout uses:

- Backend source and persistent media: `/opt/smart-mobility/backend`
- Production Compose file: `/opt/smart-mobility/docker-compose.deploy.yml`
- Repository Compose override: `docker-compose.production.override.yml`
- Production Dockerfile: `/opt/smart-mobility/backend.deploy.Dockerfile`
- Live Django services: `malawi-web-1`, `malawi-worker-1`, `malawi-beat-1`

## Deploy directly from a PC

Requirements: Python 3, `rsync`, Docker build tools on the server, and verified
SSH access. The SSH account must be able to update the backend and manage the
production Docker services. From the repository root:

```sh
export DEPLOY_HOST=201.79.45.60
export DEPLOY_USER=root
bash ./scripts/deploy-production.sh
```

The script syntax-checks Python, syncs source to the server, builds the
production image, runs backend regression tests and database migrations, then
recreates only the web/worker/beat services. It leaves Postgres, Redis,
`.env*`, Django uploads in `media/`, and Git metadata in place. Before applying
migrations it creates a compressed Postgres backup under
`/opt/smart-mobility/backups/backend-deploy/`. Database migrations are
persistent changes; review them before deployment.

## Deploy through GitHub

Pushing to `main` runs the production deployment workflow. It checks out that
commit on a self-hosted runner installed on the production server and uses the
same deployment script. No server SSH key or deployment credential is stored
in GitHub. The live backend folder contains persistent uploads and deployment
state, so a raw `git pull` there is not the deployment mechanism.

Register a repository-level runner in **Settings → Actions → Runners** and
install its service on the production host. Repeat registration for each
repository using the workflow. The runner needs Linux x64 labels including
`smr-production`, Python 3, rsync, Docker/Compose, and permission to update the
backend and manage its Docker services. Use a dedicated runner identity where
practical; Docker access is effectively root-level production access. Protect
`main`, configure the `production` environment to allow only `main`, restrict
runner and workflow access, and do not run untrusted fork or pull-request
workflows on this host. Enter the short-lived runner-registration token on the
host only; do not store it in the repository.

You can also run the workflow manually under
**Actions → Deploy backend → Run workflow**; it is restricted to `main`.

## Runtime safety and rollback

The deployment uses a narrow source sync and excludes `.env*`, `.git`, `media`,
static output, and generated mobile build/dependency directories. It never
deletes or recreates the database or Redis services. The Compose override
publishes the API at `127.0.0.1:8001`, as expected by the host Nginx proxy.
Migration failures stop the deployment before the web services are recreated.

The backend Docker build also uses the repository's `.dockerignore` so local
environment files, media uploads, Git metadata, and generated mobile artifacts
are not copied into the production image.

For code rollback, redeploy a previously successful commit and run its
migrations forward. Do not blindly reverse database migrations or delete
uploaded media. Flutter releases remain a separate signing and app-store
submission process. The direct PC path uses SSH, keeping the PC's private key
on the PC rather than in GitHub.

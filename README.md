Vehix Backend — Setup & Production Guide
======================================

For the production PC/SSH deployment and push-triggered GitHub Actions workflow,
see [DEPLOYMENT.md](./DEPLOYMENT.md).

This README explains how to run and deploy the Vehix backend locally and in production. It is written for beginners and focuses on using the Docker setup included in `config/docker-compose.yml`.

Quick overview
- `daphne` serves ASGI (websocket + HTTP).
- `redis` is used for Channels (real-time) and Celery (task queue).
- `celery` performs background tasks (flush locations, notifications, heavy work).
- `postgres` is the production database.

Prerequisites (local machine)
- Git
- Docker and Docker Compose (for the recommended quick setup)
- Alternatively: Python 3.11, Postgres, Redis installed locally

Files you should know about
- `config/docker-compose.yml` — runs Postgres, Redis, Daphne (web), Celery worker, and Celery Beat.
- `config/Dockerfile` — builds the app image.
- `config/entrypoint.sh` — runs migrations and collectstatic before starting the server.
- `config/celery.py` — Celery app configuration.
- `config/tasks.py` — Celery tasks (flush locations, clear cache).
- `config/management/commands/flush_locations.py` — management command to flush cached locations into DB.
- `config/management/commands/clear_cache.py` — management command to clear cache.

Environment variables
Create a `.env` file at the project root (next to `manage.py`) or set env vars in your host/container. A `.env.example` is provided.

Important variables (minimum):
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` — Postgres credentials (docker-compose sets defaults).
- `DATABASE_HOST`, `DATABASE_PORT` — used by `entrypoint.sh`.
- `REDIS_URL` — redis connection string (docker-compose uses `redis://redis:6379/1`).
- `SECRET_KEY` — keep secret and set in production.
- `DEBUG` — set `False` in production.

Run locally with Docker (recommended)
1. Copy `.env.example` to `.env` and edit values as necessary.
2. From `config/` directory run:

```bash
docker-compose up --build
```

This starts:
- `http://localhost:8000` (Daphne)
- Celery worker and Celery Beat inside containers

Run services individually (useful for debugging)

```bash
# Start the web server (daphne)
docker-compose run --service-ports web

# Start a celery worker
docker-compose run worker

# Start celery beat (scheduler)
docker-compose run beat
```

Run without Docker (developer)
1. Create a virtualenv and install `requirements.txt`.
2. Ensure Postgres and Redis are running locally and environment variables are set.
3. Run migrations and start services:

```bash
python manage.py migrate
python manage.py runserver 0.0.0.0:8000  # development server (not for production)

# Start redis and celery separately
celery -A config worker --loglevel=info
celery -A config beat --loglevel=info --scheduler django_celery_beat.schedulers:DatabaseScheduler
```

Management commands (useful)
- Flush ephemeral rodie locations into DB:

```bash
python manage.py flush_locations
```

- Clear cache (careful — this clears cached keys globally):

```bash
python manage.py clear_cache
```

How the realtime & scaling pieces work
- High-frequency updates (eg. rodie location) are written to Redis cache keys like `rodie_loc:{id}` to avoid hammering the DB.
- A periodic Celery task `config.tasks.flush_locations_task` flushes cached locations into the DB every 30s.
- Request-offer state is stored in cache with keys like `request_status:{id}` so the offer flow can avoid heavy `SELECT ... FOR UPDATE` DB polling.
- Use Redis + Celery to handle background and long-running work so the web processes stay responsive.

Production recommendations (concise, beginner-friendly)
1. Security
   - Set `DEBUG=False` and ensure `SECRET_KEY` is an env var.
   - Use HTTPS via a reverse proxy (Nginx / Traefik).
2. Database
   - Use managed Postgres or run Postgres on a dedicated host.
   - Use connection pooling (pgbouncer) to avoid opening many DB connections.
   - Add indexes to frequently queried columns (e.g., `ServiceRequest.status`).
3. Redis
   - Use a dedicated Redis instance or managed Redis service (AWS, Azure, etc.).
   - Do not use `cache.clear()` in production; prefer deleting target keys or using TTLs.
4. Workers
   - Run multiple Celery workers for concurrency. Pin CPU/memory resources per worker.
   - Use Celery Beat (or a scheduler) to run periodic tasks like flushing locations.
5. ASGI & static
   - Use Daphne/Gunicorn + an ASGI worker pool. Run multiple Daphne instances behind a load balancer.
   - Serve static files via CDN or Nginx to offload from the application.
6. Observability
   - Add monitoring (Prometheus) and logs aggregation (ELK, Datadog).
   - Add tracing / error reporting (Sentry).

Microservice split suggestions (to scale independently)
- Location service: handle location writes, caching and aggregation; expose an HTTP or gRPC API.
- Matching service: the `notify_rodies` sequential offer logic and OSRM routing calls; run as a separate service or a Celery queue with dedicated workers.
- Payments service: isolate payment flows (Pesapal) and wallet settlement to reduce blast radius.
- Notifications service: process notifications and push events to Channels or external push providers.

Next steps I can implement for you
- Replace `clear_cache` with a safer pattern-based deletion function.
- Convert `_sequential_offers` fully into a Celery workflow (non-blocking) and add locking via Redis.
- Add `nginx` and `pgbouncer` to `docker-compose` and create a production-ready compose file.

If you'd like, I can implement any of the next steps now and provide exact commands to deploy.

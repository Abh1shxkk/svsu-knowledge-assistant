# Test deployment

Runs on the shared test server as three memory-limited containers (database, API, website) behind
the server's Caddy, at `https://svsu.54-173-64-109.sslip.io` (`/api` goes to the API).

## Update the server
1. **Website** (built on a developer machine; the server is too small to build it):
   ```bash
   cd frontend
   NEXT_DIST_DIR=.next-prod NEXT_PUBLIC_API_URL=/api npx next build
   # bundle = .next-prod/standalone + .next-prod/static (into .next-prod/static) + public
   ```
   Copy the bundle to `~/svsu/deploy/web/` on the server.
2. **API:** on the server, `cd ~/svsu && git pull && cd deploy && sudo docker compose up -d --build api`.

## On the server
- `~/svsu/deploy/.env` holds `DB_PASSWORD`, `OPENAI_API_KEY`, `JWT_SECRET`, `CORS_ORIGINS` (never committed).
- Create an administrator: `sudo docker compose exec api python -m app.cli create-admin --login-id <id> --name "<name>"`.
- Back up: `sudo docker compose exec db pg_dump -U svsu -Fc svsu_assistant > svsu-$(date +%F).dump`.
- Logs: `sudo docker compose logs -f api`.
- The Caddy block lives in `/home/ubuntu/caddy/Caddyfile` (reload: `sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile`).

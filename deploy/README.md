# Test deployment

Runs on the shared test server as three memory-limited containers (database, API, website) behind
the server's Caddy, at `https://svsu.54-173-64-109.sslip.io` (`/api` goes to the API).

## Automatic deploys
Every push to `main` runs the tests; if they pass, GitHub Actions builds the website, copies it to the
server, updates the API and checks the live site (`deploy` job in `.github/workflows/ci.yml`). It
connects with its own deploy key (secret `DEPLOY_SSH_KEY`; its public half is the line marked
`github-actions-deploy svsu` in the server's `~/.ssh/authorized_keys`). Remove that line to revoke it.
Roll back the website: on the server, `cd ~/svsu/deploy && rm -rf web && mv web.old web && sudo docker compose restart web`.

## Update the server by hand (if Actions is unavailable)
1. **Website** (built on a developer machine; the server is too small to build it), from Git Bash:
   `KEY=/path/to/key.pem bash deploy/push-web.sh`
2. **API:** on the server, `cd ~/svsu && git pull && cd deploy && sudo docker compose up -d --build api`.

## On the server
- `~/svsu/deploy/.env` holds `DB_PASSWORD`, `OPENAI_API_KEY`, `JWT_SECRET`, `CORS_ORIGINS` (never committed).
- Create an administrator: `sudo docker compose exec api python -m app.cli create-admin --login-id <id> --name "<name>"`.
- Back up: `sudo docker compose exec db pg_dump -U svsu -Fc svsu_assistant > svsu-$(date +%F).dump`.
- Logs: `sudo docker compose logs -f api`.
- The Caddy block lives in `/home/ubuntu/caddy/Caddyfile` (reload: `sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile`).

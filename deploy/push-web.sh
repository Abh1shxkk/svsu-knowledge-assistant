#!/usr/bin/env bash
# Build the website on this machine and put it live on the test server.
#   KEY=/path/to/key.pem deploy/push-web.sh            (run from the project folder, in Git Bash)
set -euo pipefail
SERVER=${SERVER:-ubuntu@54.173.64.109}
KEY=${KEY:?set KEY to the server key file}
export MSYS_NO_PATHCONV=1 NEXT_DIST_DIR=.next-prod NEXT_PUBLIC_API_URL=/api NEXT_TELEMETRY_DISABLED=1  # keep "/api" as-is on Windows

cd "$(dirname "$0")/../frontend"
rm -rf .next-prod && npx next build
rm -rf ../.tmp/web && mkdir -p ../.tmp
cp -r .next-prod/standalone ../.tmp/web
cp -r .next-prod/static ../.tmp/web/.next-prod/static
cp -r public ../.tmp/web/public
cd ../.tmp && tar -czf web.tgz -C web .
scp -q -i "$KEY" web.tgz "$SERVER:svsu/deploy/web.tgz"
ssh -i "$KEY" "$SERVER" 'cd ~/svsu/deploy && rm -rf web && mkdir web && tar -xzf web.tgz -C web && rm web.tgz && sudo docker compose restart web'
echo "Website updated."

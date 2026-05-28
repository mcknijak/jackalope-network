#!/usr/bin/env bash
#
# Configure CouchDB for the Obsidian Self-hosted LiveSync plugin.
# Run this once after `docker compose up -d` finishes the first start.
#
# Reads COUCHDB_USER and COUCHDB_PASSWORD from .env in this directory.

set -euo pipefail

cd "$(dirname "$0")"

# Load .env
set -a
source .env
set +a

URL="http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@localhost:5984"

# CouchDB needs to be reachable on the host. The compose file does not publish
# the port, so we exec into the container to make the calls instead.
exec_curl() {
  docker compose exec -T couchdb curl -fsS -X PUT \
    "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984$1" \
    -H "Content-Type: application/json" \
    -d "$2"
}

echo ">>> Requiring valid users on all endpoints"
exec_curl "/_node/_local/_config/chttpd/require_valid_user" '"true"'
exec_curl "/_node/_local/_config/chttpd_auth/require_valid_user" '"true"'

echo ">>> Setting WWW-Authenticate realm"
exec_curl "/_node/_local/_config/httpd/WWW-Authenticate" '"Basic realm=\"couchdb\""'

echo ">>> Enabling CORS"
exec_curl "/_node/_local/_config/httpd/enable_cors" '"true"'
exec_curl "/_node/_local/_config/cors/origins" '"app://obsidian.md,capacitor://localhost,http://localhost"'
exec_curl "/_node/_local/_config/cors/credentials" '"true"'
exec_curl "/_node/_local/_config/cors/methods" '"GET, PUT, POST, HEAD, DELETE"'
exec_curl "/_node/_local/_config/cors/headers" '"accept, authorization, content-type, origin, referer, x-csrf-token"'

echo ">>> Raising max document size for LiveSync chunks"
exec_curl "/_node/_local/_config/chttpd/max_http_request_size" '"4294967296"'

echo
echo "CouchDB CORS configured. Now create the database the plugin will use:"
echo "  curl -X PUT https://couchdb.jackalope.network/obsidian -u ${COUCHDB_USER}:<password>"
echo
echo "Then configure the Self-hosted LiveSync plugin in Obsidian:"
echo "  URI:       https://couchdb.jackalope.network"
echo "  Username:  ${COUCHDB_USER}"
echo "  Password:  (from .env)"
echo "  Database:  obsidian"

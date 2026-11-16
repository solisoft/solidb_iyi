#!/bin/sh
# Runs the driver's tests against a throwaway server.
#
#   ./run_tests.sh [path to solidb]
#
# The server is started on SOLIDB_TEST_PORT (default 6799) with an empty
# data directory, and stopped by its pid when the tests end.
set -eu
cd "$(dirname "$0")"

server="${1:-${SOLIDB_BIN:-solidb}}"
port="${SOLIDB_TEST_PORT:-6799}"
data="$(mktemp -d)"
password="iyi-driver-test"

SOLIDB_ADMIN_PASSWORD="$password" "$server" --host 127.0.0.1 --port "$port" --data-dir "$data" >"$data/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -rf "$data"' EXIT

tries=0
until curl -fs "http://127.0.0.1:$port/_api/health" >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -gt 100 ] || ! kill -0 "$pid" 2>/dev/null; then
    echo "run_tests.sh: the server did not start; its log:" >&2
    cat "$data/server.log" >&2
    exit 1
  fi
  sleep 0.1
done

SOLIDB_TEST_PORT="$port" SOLIDB_TEST_PASSWORD="$password" iyi test

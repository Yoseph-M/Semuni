#!/usr/bin/env bash
# Phase 9 evidence tool: probe the running NestJS API and print
# METHOD + ENDPOINT + HTTP STATUS for the passenger/driver read paths.
#
# Read-only: it logs in (which is how it gets a token) and then GETs and quotes.
# No money moves, nothing is created.
#
# Usage:
#   BASE=http://127.0.0.1:3100/api/v1 \
#   PASSENGER_USERNAME=... PASSENGER_PASSWORD=... \
#   DRIVER_USERNAME=... DRIVER_PASSWORD=... \
#   ./backend/tools/phase9-live-endpoint-probe.sh

set -uo pipefail

BASE="${BASE:-http://127.0.0.1:3100/api/v1}"
PASSENGER_USERNAME="${PASSENGER_USERNAME:-smoke.passenger}"
PASSENGER_PASSWORD="${PASSENGER_PASSWORD:-SmokePassenger#2026}"
DRIVER_USERNAME="${DRIVER_USERNAME:-}"
DRIVER_PASSWORD="${DRIVER_PASSWORD:-}"

extract_token() { # responses are wrapped in {"data": ...}
  python3 -c 'import json,sys;d=json.load(sys.stdin);d=d.get("data",d) if isinstance(d,dict) else d;print((d or {}).get("accessToken",""))'
}

probe() { # probe <label> <token> <method> <path> [body]
  local label="$1" token="$2" method="$3" path="$4" body="${5:-}"
  local code
  if [[ -n "$body" ]]; then
    code=$(curl -s -o /tmp/probe-body.json -w '%{http_code}' \
      -X "$method" "$BASE$path" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' \
      -d "$body")
  else
    code=$(curl -s -o /tmp/probe-body.json -w '%{http_code}' \
      -X "$method" "$BASE$path" -H "Authorization: Bearer $token")
  fi
  printf '%-11s %-45s -> %s   %s\n' "$method" "$path" "$code" "$label"
}

echo "backend: $BASE"
echo

echo "-- public --"
probe 'liveness' '' GET /health
probe 'readiness' '' GET /health/ready

echo
echo "-- passenger --"
login=$(curl -s -X POST "$BASE/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$PASSENGER_USERNAME\",\"password\":\"$PASSENGER_PASSWORD\",\"role\":\"PASSENGER\"}")
token=$(printf '%s' "$login" | extract_token)
if [[ -z "$token" ]]; then
  echo "passenger login failed: $login"
  exit 1
fi

probe 'identity + role' "$token" GET /auth/me
probe 'own profile' "$token" GET /passengers/me
probe 'wallet balance' "$token" GET /wallet
probe 'wallet ledger' "$token" GET /wallet/transactions
probe 'routes' "$token" GET /routes
probe 'trips (names + amountPaid)' "$token" GET /trips
probe 'payments' "$token" GET /payments

route_id=$(curl -s "$BASE/routes" -H "Authorization: Bearer $token" |
  python3 -c 'import json,sys;d=json.load(sys.stdin);r=(d["data"] if isinstance(d,dict) and "data" in d else d);print(r[0]["id"] if r else "")')
stops=$(curl -s "$BASE/routes/$route_id" -H "Authorization: Bearer $token" |
  python3 -c 'import json,sys;d=json.load(sys.stdin);r=d.get("data",d) if isinstance(d,dict) else d;s=r.get("stops") or [];o=s[0]["id"] if s else "";t=s[-1]["id"] if len(s)>=2 else "";print(o+" "+t)')
if [[ -n "$route_id" && -n "$stops" ]]; then
  read -r origin_stop destination_stop <<<"$stops"
  probe 'official fare quote' "$token" POST /fares/calculate \
    "{\"routeId\":\"$route_id\",\"originStopId\":\"$origin_stop\",\"destinationStopId\":\"$destination_stop\"}"
fi

echo
echo "-- driver --"
if [[ -n "$DRIVER_USERNAME" && -n "$DRIVER_PASSWORD" ]]; then
  dlogin=$(curl -s -X POST "$BASE/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$DRIVER_USERNAME\",\"password\":\"$DRIVER_PASSWORD\",\"role\":\"DRIVER\"}")
  dtoken=$(printf '%s' "$dlogin" | extract_token)
  if [[ -z "$dtoken" ]]; then
    echo "driver login failed: $dlogin"
  else
    probe 'driver profile' "$dtoken" GET /drivers/me
    probe 'earnings (ETB)' "$dtoken" GET /drivers/me/earnings
    probe 'transactions' "$dtoken" GET /drivers/me/transactions
    probe 'assigned routes' "$dtoken" GET /drivers/me/routes
    probe 'outstanding withdrawals' "$dtoken" GET /drivers/me/withdrawals
    probe 'driver discovery (passenger token)' "$token" GET /drivers/available
  fi
else
  echo "(set DRIVER_USERNAME/DRIVER_PASSWORD to include the driver rail)"
fi

#!/bin/bash

# Tests for `omarchy-remmina list` against fixture profiles.
#
#   test/list.test.sh
#
# A .remmina file holds the saved password beside the address, so the one thing
# the list must never do is carry it. Runs the helper with its config, data and
# state pointed at a temporary folder — no Remmina, no shell.

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
HELPER="$HERE/../bin/omarchy-remmina"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data" XDG_STATE_HOME="$TMP/state"
PROFILES="$XDG_DATA_HOME/remmina"
mkdir -p "$PROFILES"

PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     %s\n' "$1" "${2-}"; }

check_eq() {
  local what="$1" got="$2" want="$3"
  [[ $got == "$want" ]] && ok "$what" || no "$what" "got [$got] want [$want]"
}

field() { printf '%s' "$OUT" | jq -r --arg n "$1" ".rows[] | select(.name == \$n) | .$2"; }

echo "list: no profiles"
OUT=$(timeout 5 "$HELPER" list)
check_eq "an empty folder lists nothing" "$(printf '%s' "$OUT" | jq -c .rows)" "[]"

cat > "$PROFILES/lab_rdp.remmina" <<'INI'
[remmina]
password=c2VjcmV0LXZhbHVl
name=lab
group=home
server=10.0.0.2
protocol=RDP
username=andre
domain=CORP
INI

cat > "$PROFILES/box.remmina" <<'INI'
[remmina]
protocol=SSH
server=box.example:2222
ssh_password=another-secret
INI

echo
echo "list: rows"
OUT=$(timeout 5 "$HELPER" list)
check_eq "two profiles"                     "$(printf '%s' "$OUT" | jq '.rows | length')" "2"
check_eq "sorted by name"                   "$(printf '%s' "$OUT" | jq -r '[.rows[].name] | join(",")')" "box,lab"
check_eq "address and group make the sub"   "$(field lab sub)" "rdp://andre@10.0.0.2 · home"
check_eq "no user means no @"               "$(field box sub)" "ssh://box.example:2222"
check_eq "an unnamed profile uses its file" "$(field box file)" "$PROFILES/box.remmina"
check_eq "protocol is lowercased"           "$(field lab protocol)" "rdp"

if printf '%s' "$OUT" | grep -qE 'c2VjcmV0|another-secret|password|CORP'; then
  no "nothing outside the allowed keys is listed" "found a stored value in the payload"
else
  ok "nothing outside the allowed keys is listed"
fi

echo
echo "list: recent"
check_eq "nothing is recent yet" "$(printf '%s' "$OUT" | jq '[.rows[] | select(.recent)] | length')" "0"

mkdir -p "$XDG_STATE_HOME/omarchy-remmina"
printf '{"version":1,"files":{"%s":100,"%s":200}}' "$PROFILES/lab_rdp.remmina" "$PROFILES/box.remmina" \
  > "$XDG_STATE_HOME/omarchy-remmina/recent.json"
OUT=$(timeout 5 "$HELPER" list)
check_eq "the latest connection ranks first" "$(field box rank)" "0"
check_eq "the one before ranks second"       "$(field lab rank)" "1"

OUT=$(OMARCHY_REMMINA_RECENT=1 timeout 5 "$HELPER" list)
check_eq "only RECENT_MAX are lifted"        "$(field lab recent)" "false"

timeout 5 "$HELPER" forget "$PROFILES/box.remmina"
OUT=$(timeout 5 "$HELPER" list)
check_eq "forget drops a profile from recent" "$(field box recent)" "false"

echo
echo "connect: only profiles in the folder"
# notify-send would pop up a real notification; stub it out.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/notify-send"
chmod +x "$TMP/bin/notify-send"
touch "$TMP/elsewhere.remmina"
PATH="$TMP/bin:$PATH" timeout 5 "$HELPER" connect "$TMP/elsewhere.remmina"
check_eq "a profile outside the folder is refused" "$?" "1"
PATH="$TMP/bin:$PATH" timeout 5 "$HELPER" edit "$PROFILES/../remmina/../../config"
check_eq "a path that climbs out is refused" "$?" "1"

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1

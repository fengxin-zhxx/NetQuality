#!/usr/bin/env bash
# Offline regression tests for NetQuality issue #41; no network or root needed.
set -e
script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/net.sh"
bash -n "$script"
# Load only the functions under test, not the script's main entry point.
source <(sed -n '/^nexttrace_init_mode(){/,/^}/p; /^nexttrace_hop_rows(){/,/^}/p; /^nexttrace_test(){/,/^}/p; /^nexttrace_route(){/,/^}/p' "$script")
declare -A AS_MAPPING=()
declare -a nexttrace_mode_args=()
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail(){ echo "FAIL: $*" >&2; exit 1; }
assert_eq(){ [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }
# Mock dependencies. Record probe calls on disk because command substitutions
# run in subshells. No actual packets are sent and no retry sleeps occur.
timeout(){ shift 3; "$@"; }
sleep(){ :; }
nexttrace(){
if [[ $1 == --help ]];then
if [[ $version == new ]];then echo '  -k --traceroute'; else echo '  --raw'; fi
return 0
fi
printf '%s\n' "$*" >> "$tmp/calls"
case "$fixture" in
error) printf '%s\n' '*please try again later*'; return 1;;
retry) if [[ $(wc -l < "$tmp/calls") -eq 1 ]];then echo 'please try again later'; return 1; fi;;
empty) echo 'traceroute to 203.0.113.3'; printf '%s\n' '1|*||||||' '2|*||||||||||'; return 0;;
text-empty) echo '192.0.2.1 -> 203.0.113.3'; echo '1 *'; return 0;;
esac
if [[ $version == new ]];then echo '192.0.2.1 -> 203.0.113.3'; else echo 'traceroute to 203.0.113.3'; fi
if [[ " $* " == *' --raw '* ]];then
printf '%s\n' 'metadata|not a hop' '1|192.0.2.1||1.0|64500|日本|东京|东京||ExampleNet||' '2|*||||||' '2|59.43.0.1||10.0|4809|中国|上海|上海||中国电信||' '3|203.0.113.3||11.0|4809|中国|上海|上海||中国电信||'
else
printf '\033[32m%s\033[0m\n' '1 192.0.2.1 AS64500 [ExampleNet] 日本 东京' '  1.20 ms' '2 2001:db8::2 AS4809 中国 上海' '  10.50 ms'
fi
}
reset_calls(){ : > "$tmp/calls"; }
assert_calls(){ assert_eq "$(wc -l < "$tmp/calls" | tr -d '[:space:]')" "$1"; }
for version in old new;do
fixture=ok
nexttrace_init_mode
reset_calls
assert_eq "$(nexttrace_test example.test tcp 1 4)" '1 AS64500 CN2GIA'
assert_calls 1
if [[ $version == new ]];then grep -q -- '--traceroute' "$tmp/calls" || fail 'new version did not get --traceroute'; else ! grep -q -- '--traceroute' "$tmp/calls" || fail 'old version got unsupported flag'; fi
reset_calls
result=$(nexttrace_route example.test 1 2 6)
assert_eq "$result" $'|2|1|1.20ms|192.0.2.1|AS64500|[ExampleNet]|日本 东京|\n|2|2|10.50ms|2001:db8::2|AS4809||中国 上海|'
assert_calls 1
echo "PASS: $version headers, raw classification, detailed IPv6 rows, single attempt"
done
fixture=retry
reset_calls
assert_eq "$(nexttrace_test example.test tcp 1 4)" '1 AS64500 CN2GIA'
assert_calls 2
echo 'PASS: temporary API failure retries and recovers'
for fixture in empty error;do
reset_calls
assert_eq "$(nexttrace_test example.test tcp 1 4)" '1 NoData NoData'
assert_calls 10
echo "PASS: $fixture remains NoData after retry limit"
done
for fixture in text-empty error;do
reset_calls
assert_eq "$(nexttrace_route example.test 1 2 4)" ''
assert_calls 10
echo "PASS: $fixture does not produce detailed hops"
done

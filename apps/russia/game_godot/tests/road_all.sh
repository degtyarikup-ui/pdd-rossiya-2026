#!/bin/sh
# Every road question (roads/road_scenes.json) in one headless run each: the car drives up to the
# question, the autopilot (--auto) answers it, the run ends TEST_TAIL game seconds later.
#   sh game_godot/tests/road_all.sh [parallel]      (default 4 at once)
# A question passes when its log shows the question and its answer, and no script error.
# Logs and the summary go to output/godot-roads/ (git-ignored).
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/../output/godot-roads"
jobs="${1:-4}"
mkdir -p "$out"
rm -f "$out"/*.log "$out/summary.txt"
ids=$(python3 -c "import json,sys; print('\n'.join(s['id'] for s in json.load(open(sys.argv[1]))['scenes']))" "$here/roads/road_scenes.json")
printf '%s\n' $ids | xargs -P "$jobs" -I{} sh -c 'godot --headless --path "$1" --quit-after 6000 -- --road={} --auto > "$2/{}.log" 2>&1' sh "$here" "$out"
: > "$out/summary.txt"
pass=0
fail=0
for id in $ids; do
	log="$out/$id.log"
	if grep -q "SCRIPT ERROR" "$log"; then
		state="FAIL script error"
	elif grep -q "\[road\] question $id " "$log" && grep -q "\[road\] answer" "$log" && grep -q "\[road\] test end" "$log"; then
		state="ok"
	else
		state="FAIL no answer"
	fi
	end=$(grep "\[road\] test end" "$log" | sed 's/.*test end //')
	kind=$(grep "\[road\] question $id " "$log" | sed 's/.*kind \([a-z_]*\).*/\1/')
	echo "$state  $id  $kind  $end" >> "$out/summary.txt"
	case "$state" in
		ok) pass=$((pass + 1)) ;;
		*) fail=$((fail + 1)) ;;
	esac
done
cat "$out/summary.txt"
echo "road questions: $pass ok, $fail failed"
[ "$fail" -eq 0 ]

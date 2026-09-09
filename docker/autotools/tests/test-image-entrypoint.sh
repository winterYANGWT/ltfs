#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
entrypoint="$repo_root/docker/autotools/scripts/runtime-entrypoint.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ltfs-image-entrypoint.XXXXXX")
cleanup()
{
	rm -rf -- "$test_root"
}
trap cleanup EXIT INT TERM

cat >"$test_root/self-test" <<'EOF'
#!/usr/bin/env bash
printf 'self-test:%s\n' "$*" >>"$ENTRYPOINT_TEST_LOG"
EOF
chmod +x "$test_root/self-test"

cat >"$test_root/command" <<'EOF'
#!/usr/bin/env bash
printf 'command:%s\n' "$*" >>"$ENTRYPOINT_TEST_LOG"
EOF
chmod +x "$test_root/command"

ENTRYPOINT_TEST_LOG="$test_root/log" \
LTFS_IMAGE_ROLE=runtime \
LTFS_SELF_TEST_COMMAND="$test_root/self-test" \
	"$entrypoint" self-test alpha beta

grep -Fxq 'self-test:alpha beta' "$test_root/log"

: >"$test_root/log"
ENTRYPOINT_TEST_LOG="$test_root/log" \
LTFS_IMAGE_ROLE=dev \
LTFS_SELF_TEST_COMMAND="$test_root/self-test" \
LTFS_SELF_TEST_ON_START=1 \
	"$entrypoint" "$test_root/command" custom

expected=$'self-test:\ncommand:custom'
actual=$(cat "$test_root/log")
if [[ "$actual" != "$expected" ]]; then
	printf 'unexpected on-start dispatch:\n%s\n' "$actual" >&2
	exit 1
fi

set +e
LTFS_IMAGE_ROLE=runtime \
LTFS_SELF_TEST_COMMAND="$test_root/self-test" \
LTFS_SELF_TEST_ON_START=invalid \
	"$entrypoint" "$test_root/command" >/dev/null 2>&1
status=$?
set -e
if [[ "$status" -ne 64 ]]; then
	printf 'invalid LTFS_SELF_TEST_ON_START must exit 64, got %s\n' "$status" >&2
	exit 1
fi

printf 'Autotools image entrypoint tests passed.\n'

#!/usr/bin/env bash

set -euo pipefail

# An EOL image exists so it can run on an old host. If its binaries required a
# newer glibc than the old host provides, the image would build fine and still
# be useless there. This check makes that failure mode loud at build time.
#
# LTFS_MAX_GLIBC_SYMBOL is the highest GLIBC_ symbol version the installed
# binaries may require, declared per distribution by the build definition.
stage_dir=${1:?usage: check-glibc-floor STAGE_DIR}
max_symbol=${LTFS_MAX_GLIBC_SYMBOL:?LTFS_MAX_GLIBC_SYMBOL must be set}

if [[ ! $max_symbol =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
	printf 'LTFS_MAX_GLIBC_SYMBOL must look like 2.17: %s\n' "$max_symbol" >&2
	exit 64
fi

# sort -V orders version strings, so the highest required symbol sorts last.
highest_of()
{
	readelf -V "$1" 2>/dev/null |
		grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' |
		sed 's/^GLIBC_//' |
		sort -V |
		tail -1
}

status=0
checked=0
while IFS= read -r -d '' binary; do
	# Skip anything that is not a dynamically linked ELF object.
	if ! readelf -h "$binary" >/dev/null 2>&1; then
		continue
	fi
	required=$(highest_of "$binary")
	if [[ -z "$required" ]]; then
		continue
	fi
	checked=$((checked + 1))
	if [[ "$(printf '%s\n%s\n' "$max_symbol" "$required" | sort -V | tail -1)" != "$max_symbol" ]]; then
		printf 'requires GLIBC_%s (max GLIBC_%s): %s\n' \
			"$required" "$max_symbol" "$binary" >&2
		status=1
	fi
done < <(find "$stage_dir" -type f \( -perm -u+x -o -name '*.so*' \) -print0)

if ((checked == 0)); then
	printf 'no ELF binaries found below %s\n' "$stage_dir" >&2
	exit 1
fi

if ((status != 0)); then
	printf 'glibc floor check failed; this image would not run on its target hosts\n' >&2
	exit 1
fi

printf 'glibc floor check passed: %d binaries require at most GLIBC_%s\n' \
	"$checked" "$max_symbol"

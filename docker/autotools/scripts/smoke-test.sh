#!/usr/bin/env bash

set -euo pipefail

# Validate installed artifacts, configuration, and dynamic linkage without mounting LTFS.
# EXPECT_MINIMAL_RUNTIME additionally rejects development tools and build metadata.
prefix=${LTFS_PREFIX:-/usr/local}
expect_minimal=${EXPECT_MINIMAL_RUNTIME:-0}
expect_file_default=${EXPECT_FILE_DEFAULT:-0}
expect_ordered_copy=${EXPECT_ORDERED_COPY:-$expect_minimal}

# The public command-line tools and the file backend form the minimum installation contract.
for binary in ltfs mkltfs ltfsck; do
	path="$prefix/bin/$binary"
	if [[ ! -x "$path" ]]; then
		printf 'missing executable: %s\n' "$path" >&2
		exit 1
	fi
done

ordered_copy="$prefix/bin/ltfs_ordered_copy"
if [[ ! -x "$ordered_copy" ]]; then
	printf 'missing executable: %s\n' "$ordered_copy" >&2
	exit 1
fi

file_plugin=$(find "$prefix/lib" \( -type f -o -type l \) -name 'libtape-file.so' -print -quit)
if [[ -z "$file_plugin" ]]; then
	printf 'missing file backend plugin below %s/lib\n' "$prefix" >&2
	exit 1
fi

# Runtime images must explicitly select the file backend when requested by their build stage.
config_file="$prefix/etc/ltfs.conf"
if [[ ! -f "$config_file" ]]; then
	printf 'missing LTFS configuration: %s\n' "$config_file" >&2
	exit 1
fi
if ! grep -Eq '^plugin[[:space:]]+tape[[:space:]]+file[[:space:]]+' "$config_file"; then
	printf 'file backend is not declared in %s\n' "$config_file" >&2
	exit 1
fi
if [[ "$expect_file_default" == 1 ]] \
	&& ! grep -Eq '^default[[:space:]]+tape[[:space:]]+file[[:space:]]*$' "$config_file"; then
	printf 'file backend is not the default tape backend in %s\n' "$config_file" >&2
	exit 1
fi

"$prefix/bin/ltfs" --help >/dev/null
"$prefix/bin/mkltfs" --help >/dev/null
"$prefix/bin/ltfsck" --help >/dev/null
if [[ "$expect_ordered_copy" == 1 ]]; then
	"$ordered_copy" --help >/dev/null
fi

link_targets=(
	"$prefix/bin/ltfs"
	"$prefix/bin/mkltfs"
	"$prefix/bin/ltfsck"
	"$file_plugin"
)
# Check every shipped executable and shared object for unresolved runtime dependencies.
while IFS= read -r -d '' library; do
	link_targets+=("$library")
done < <(find "$prefix/lib" \( -type f -o -type l \) -name '*.so*' -print0)

for target in "${link_targets[@]}"; do
	if ! ldd_output=$(ldd "$target" 2>&1); then
		printf 'ldd failed for %s:\n%s\n' "$target" "$ldd_output" >&2
		exit 1
	fi
	if grep -Fq 'not found' <<<"$ldd_output"; then
		printf 'unresolved shared library for %s:\n%s\n' "$target" "$ldd_output" >&2
		exit 1
	fi
done

# Minimal Runtime images must not retain compilers, headers, pkg-config data, or libtool archives.
if [[ "$expect_minimal" == 1 ]]; then
	for forbidden in cc gcc make autoconf automake libtool git; do
		if command -v "$forbidden" >/dev/null 2>&1; then
			printf 'minimal Runtime unexpectedly contains %s\n' "$forbidden" >&2
			exit 1
		fi
	done
	for forbidden_path in "$prefix/include" "$prefix/lib/pkgconfig" "$prefix/share/aclocal"; do
		if [[ -e "$forbidden_path" && ! -d "$forbidden_path" ]]; then
			printf 'minimal Runtime unexpectedly contains non-directory %s\n' "$forbidden_path" >&2
			exit 1
		fi
		if [[ -d "$forbidden_path" ]] \
			&& find "$forbidden_path" -mindepth 1 -print -quit | grep -q .; then
			printf 'minimal Runtime unexpectedly contains files below %s\n' "$forbidden_path" >&2
			exit 1
		fi
	done
	if find "$prefix" -type f -name '*.la' -print -quit | grep -q .; then
		printf 'minimal Runtime unexpectedly contains libtool archives\n' >&2
		exit 1
	fi
fi

printf 'LTFS Autotools smoke test passed for %s\n' "$prefix"

#!/usr/bin/env bash

set -euo pipefail

# Build contract: copy SOURCE_DIR into an isolated tree and install only into OUTPUT_DIR.
# AUTOTOOLS_PROFILE changes validation/runtime features without mutating the mounted checkout.
source_dir=${SOURCE_DIR:-/workspace}
output_dir=${OUTPUT_DIR:-/out}
profile=${AUTOTOOLS_PROFILE:-default}
configure_args_text=${CONFIGURE_ARGS:-}

if [[ ! -f "$source_dir/configure.ac" || ! -x "$source_dir/autogen.sh" ]]; then
	printf 'LTFS source tree not found at %s\n' "$source_dir" >&2
	exit 66
fi

uthash_header="$source_dir/src/libltfs/uthash_submodule/src/uthash.h"
if [[ ! -f "$uthash_header" ]]; then
	printf 'LTFS uthash submodule is missing; run: git submodule update --init --recursive\n' >&2
	exit 66
fi

# A non-empty staging destination could mix artifacts from different builds, so reject it.
if [[ -e "$output_dir" ]] && find "$output_dir" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
	printf 'OUTPUT_DIR must be empty: %s\n' "$output_dir" >&2
	exit 73
fi
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd -P)

# Explicit JOBS is validated for reproducible CI; otherwise use the detected processor count.
if [[ -n ${JOBS:-} ]]; then
	if [[ ! $JOBS =~ ^[1-9][0-9]*$ ]]; then
		printf 'JOBS must be a positive integer: %s\n' "$JOBS" >&2
		exit 64
	fi
	jobs=$JOBS
else
	jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n')
	if [[ ! $jobs =~ ^[1-9][0-9]*$ ]]; then
		jobs=1
	fi
fi

# All generated Autotools files stay in this disposable workspace.
work_root=$(mktemp -d "${TMPDIR:-/tmp}/ltfs-autotools.XXXXXX")
cleanup()
{
	rm -rf "$work_root"
}
trap cleanup EXIT INT TERM

work_source="$work_root/source"
mkdir -p "$work_source"

# Exclude VCS data and generated outputs so a dirty host tree cannot contaminate the build.
tar \
	--exclude='./.git' \
	--exclude='*/.git' \
	--exclude='./.worktrees' \
	--exclude='./.artifacts' \
	--exclude='./build' \
	--exclude='./build-*' \
	--exclude='./cmake-build-*' \
	--exclude='*/.deps' \
	--exclude='*/.libs' \
	--exclude='*/.dirstamp' \
	--exclude='*.o' \
	--exclude='*.a' \
	--exclude='*.lo' \
	--exclude='*.la' \
	--exclude='./aclocal.m4' \
	--exclude='./autom4te.cache' \
	--exclude='./build-aux' \
	--exclude='./m4' \
	--exclude='./config.h' \
	--exclude='./config.h.in' \
	--exclude='./config.log' \
	--exclude='./config.status' \
	--exclude='./configure' \
	--exclude='./libtool' \
	--exclude='./ltfs.pc' \
	--exclude='Makefile' \
	--exclude='Makefile.in' \
	--exclude='./stamp-h1' \
	--exclude='./messages/.lib' \
	--exclude='./conf/ltfs.conf' \
	--exclude='./src/ltfs' \
	--exclude='./src/ltfsmsg.h' \
	--exclude='./src/utils/ltfsck' \
	--exclude='./src/utils/mkltfs' \
	--exclude='./src/utils/ltfsindextool' \
	--exclude='./src/tape_drivers/freebsd/cam/vendor_compat.c' \
	--exclude='./src/tape_drivers/freebsd/cam/ibm_tape.c' \
	--exclude='./src/tape_drivers/freebsd/cam/hp_tape.c' \
	--exclude='./src/tape_drivers/freebsd/cam/quantum_tape.c' \
	--exclude='./src/tape_drivers/generic/file/ibm_tape.c' \
	--exclude='./src/tape_drivers/linux/lin_tape/vendor_compat.c' \
	--exclude='./src/tape_drivers/linux/lin_tape/ibm_tape.c' \
	--exclude='./src/tape_drivers/linux/lin_tape/hp_tape.c' \
	--exclude='./src/tape_drivers/linux/lin_tape/quantum_tape.c' \
	--exclude='./src/tape_drivers/linux/sg/vendor_compat.c' \
	--exclude='./src/tape_drivers/linux/sg/ibm_tape.c' \
	--exclude='./src/tape_drivers/linux/sg/hp_tape.c' \
	--exclude='./src/tape_drivers/linux/sg/quantum_tape.c' \
	--exclude='./src/tape_drivers/linux/sg/open_factor.c' \
	--exclude='./src/tape_drivers/netbsd/ibm_tape.c' \
	--exclude='./src/tape_drivers/netbsd/scsipi-ibmtape/vendor_compat.c' \
	--exclude='./src/tape_drivers/netbsd/scsipi-ibmtape/ibm_tape.c' \
	--exclude='./src/tape_drivers/netbsd/scsipi-ibmtape/hp_tape.c' \
	--exclude='./src/tape_drivers/netbsd/scsipi-ibmtape/quantum_tape.c' \
	--exclude='./src/tape_drivers/osx/iokit/vendor_compat.c' \
	--exclude='./src/tape_drivers/osx/iokit/ibm_tape.c' \
	--exclude='./src/tape_drivers/osx/iokit/hp_tape.c' \
	--exclude='./src/tape_drivers/osx/iokit/quantum_tape.c' \
	-C "$source_dir" -cf - . | tar -C "$work_source" -xf -

# Profiles centralize the intentional differences between permissive CI, strict CI, and Runtime.
configure_args=()
case "$profile" in
	default)
		;;
	strict)
		configure_args+=(
			--enable-message-checker
			--enable-warning-as-error
		)
		;;
	runtime-file)
		export DEFAULT_TAPE=file
		configure_args+=(
			--disable-snmp
			--disable-static
		)
		;;
	*)
		printf 'unknown AUTOTOOLS_PROFILE: %s\n' "$profile" >&2
		exit 64
		;;
esac

# CONFIGURE_ARGS is an advanced escape hatch and is intentionally split like shell arguments.
if [[ -n "$configure_args_text" ]]; then
	read -r -a extra_args <<<"$configure_args_text"
	configure_args+=("${extra_args[@]}")
fi
configure_args+=(--prefix=/usr/local)

printf 'Building LTFS with Autotools profile=%s jobs=%s\n' "$profile" "$jobs"
(
	cd "$work_source"
	./autogen.sh
	./configure "${configure_args[@]}"
	make -j"$jobs"
	make DESTDIR="$output_dir" install
)

# Fail before publishing if the installation contract or file backend is incomplete.
for binary in ltfs mkltfs ltfsck; do
	if [[ ! -x "$output_dir/usr/local/bin/$binary" ]]; then
		printf 'expected installed binary is missing: %s\n' "$binary" >&2
		exit 1
	fi
done

if ! find "$output_dir/usr/local/lib" \( -type f -o -type l \) -name 'libtape-file.so' -print -quit | grep -q .; then
	printf 'expected file backend plugin is missing from staging tree\n' >&2
	exit 1
fi

cat >"$output_dir/.ltfs-autotools-build" <<EOF
profile=$profile
prefix=/usr/local
jobs=$jobs
EOF

printf 'LTFS staging tree written to %s\n' "$output_dir"

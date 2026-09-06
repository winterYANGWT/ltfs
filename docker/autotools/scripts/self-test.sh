#!/usr/bin/env bash

set -euo pipefail

# This command is shipped in every formal image. Build-time validation enables
# source compilation explicitly; consumers can run lightweight role checks and
# opt into a mounted-source build when needed.
role=${LTFS_IMAGE_ROLE:-}
build_source=${LTFS_SELF_TEST_BUILD_SOURCE:-0}
require_source=${LTFS_SELF_TEST_REQUIRE_SOURCE:-0}
install_to_root=${LTFS_SELF_TEST_INSTALL_TO_ROOT:-0}
source_dir=${SOURCE_DIR:-/workspace}

require_boolean()
{
	local name=$1
	local value=$2

	case "$value" in
		0 | 1)
			;;
		*)
			printf '%s must be 0 or 1: %s\n' "$name" "$value" >&2
			exit 64
			;;
	esac
}

require_command()
{
	local name=$1

	if ! command -v "$name" >/dev/null 2>&1; then
		printf 'required command is missing: %s\n' "$name" >&2
		exit 1
	fi
}

require_boolean LTFS_SELF_TEST_BUILD_SOURCE "$build_source"
require_boolean LTFS_SELF_TEST_REQUIRE_SOURCE "$require_source"
require_boolean LTFS_SELF_TEST_INSTALL_TO_ROOT "$install_to_root"

if [[ "$install_to_root" == 1 && "$build_source" != 1 ]]; then
	printf 'LTFS_SELF_TEST_INSTALL_TO_ROOT=1 requires LTFS_SELF_TEST_BUILD_SOURCE=1\n' >&2
	exit 64
fi

case "$role" in
	ci | dev)
		for command_name in autoconf automake gcc make libtoolize python tar; do
			require_command "$command_name"
		done
		require_command icu-config
		require_command net-snmp-config
		icu-config --version >/dev/null
		net-snmp-config --cflags >/dev/null

		source_present=0
		if [[ -f "$source_dir/configure.ac" && -x "$source_dir/autogen.sh" ]]; then
			source_present=1
		fi
		if [[ "$require_source" == 1 && "$source_present" != 1 ]]; then
			printf 'LTFS source tree required for self-test at %s\n' "$source_dir" >&2
			exit 66
		fi

		if [[ "$build_source" == 1 ]]; then
			if [[ "$source_present" != 1 ]]; then
				printf 'LTFS source tree not found for requested self-test build at %s\n' "$source_dir" >&2
				exit 66
			fi

			self_test_root=$(mktemp -d "${TMPDIR:-/tmp}/ltfs-image-self-test.XXXXXX")
			cleanup_self_test()
			{
				rm -rf -- "$self_test_root"
			}
			trap cleanup_self_test EXIT INT TERM
			stage_root="$self_test_root/stage"

			SOURCE_DIR="$source_dir" \
			OUTPUT_DIR="$stage_root" \
				/usr/local/bin/ltfs-autotools-build

			if [[ "$install_to_root" == 1 ]]; then
				if [[ "$(id -u)" -ne 0 ]]; then
					printf 'root is required for LTFS_SELF_TEST_INSTALL_TO_ROOT=1\n' >&2
					exit 77
				fi
				cp -a "$stage_root"/. /
				printf '/usr/local/lib\n' >/etc/ld.so.conf.d/ltfs.conf
				ldconfig
				/usr/local/bin/ltfs-autotools-smoke-test
			fi
		fi

		if [[ "$role" == dev ]]; then
			for command_name in ccache gdb git; do
				require_command "$command_name"
			done
			python -c 'import xattr'
			if [[ "$(id -u)" -ne 0 ]]; then
				printf 'Dev self-test must run as root\n' >&2
				exit 1
			fi
			for writable_path in /workspace /out; do
				if [[ ! -w "$writable_path" ]]; then
					printf 'Dev path is not writable: %s\n' "$writable_path" >&2
					exit 1
				fi
			done
		fi
		;;
	runtime)
		for command_name in \
			/usr/local/bin/ltfs-autotools-smoke-test \
			/usr/local/bin/ltfs-autotools-format-file-backend-test \
			/usr/local/bin/ltfs-autotools-entrypoint; do
			if [[ ! -x "$command_name" ]]; then
				printf 'required Runtime self-test command is missing: %s\n' "$command_name" >&2
				exit 1
			fi
		done

		EXPECT_FILE_DEFAULT=1 \
		EXPECT_MINIMAL_RUNTIME=1 \
			/usr/local/bin/ltfs-autotools-smoke-test
		/usr/local/bin/ltfs-autotools-format-file-backend-test
		LTFS_SELF_TEST_ON_START=0 \
			/usr/local/bin/ltfs-autotools-entrypoint >/dev/null
		LTFS_SELF_TEST_ON_START=0 \
			/usr/local/bin/ltfs-autotools-entrypoint --help >/dev/null
		;;
	*)
		printf 'LTFS_IMAGE_ROLE must be ci, dev, or runtime: %s\n' "$role" >&2
		exit 64
		;;
esac

printf 'LTFS Autotools self-test passed for role=%s.\n' "$role"

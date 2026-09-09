#!/usr/bin/env bash

set -euo pipefail

# Some RPM distributions (Rocky 10, Fedora 43+) make net-snmp-config export the
# distribution's whole compiler policy, including one compound Fortify
# preprocessor token. LTFS's configure cleanup removes the definition from the
# middle of that token and leaves a bare -Wp, which gcc rejects. net-snmp also
# exports its own -Werror policy, which must not turn a dependency's warnings
# into LTFS build failures. Normalize those CFLAGS only; forward every other
# request, its output, and its exit status unchanged.
real_config=${NET_SNMP_CONFIG_REAL:-/usr/bin/net-snmp-config}
if [[ ! -x "$real_config" ]]; then
	printf 'net-snmp-config provider is not executable: %s\n' "$real_config" >&2
	exit 69
fi

if [[ $# -eq 1 && $1 == "--cflags" ]]; then
	"$real_config" "$@" |
		sed -E \
			-e 's/(^|[[:space:]])-Wp,-U_FORTIFY_SOURCE,-D_FORTIFY_SOURCE=[^[:space:]]+/\1-U_FORTIFY_SOURCE/g' \
			-e 's/(^|[[:space:]])-Werror(=[^[:space:]]+)?/\1/g' \
			-e 's/[[:space:]]+/ /g' \
			-e 's/^ //; s/ $//'
else
	exec "$real_config" "$@"
fi

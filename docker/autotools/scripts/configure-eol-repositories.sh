#!/bin/sh

set -eu

# EOL distributions stop serving packages from their normal repositories.
# Each case pins an archive location that still works. These archives are
# frozen and receive no security updates, which is the whole reason EOL
# images are limited to the runtime role.
distro=${1:?usage: configure-eol-repositories DISTRO_ID}

case "$distro" in
	centos7)
		rm -f /etc/yum.repos.d/*.repo
		cat >/etc/yum.repos.d/vault.repo <<'REPO'
[base]
name=CentOS 7.9.2009 vault - base
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/os/$basearch/
enabled=1
gpgcheck=0

[updates]
name=CentOS 7.9.2009 vault - updates
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=0

[extras]
name=CentOS 7.9.2009 vault - extras
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=0
REPO
		;;
	fedora28)
		base=https://dl.fedoraproject.org/pub/archive/fedora/linux
		rm -f /etc/yum.repos.d/*.repo
		cat >/etc/yum.repos.d/archive.repo <<REPO
[releases]
name=Fedora 28 archive - releases
baseurl=${base}/releases/28/Everything/x86_64/os/
enabled=1
gpgcheck=0

[updates]
name=Fedora 28 archive - updates
baseurl=${base}/updates/28/Everything/x86_64/
enabled=1
gpgcheck=0
REPO
		;;
	debian9 | debian10)
		codename=$([ "$distro" = debian9 ] && echo stretch || echo buster)
		cat >/etc/apt/sources.list <<APT
deb [trusted=yes] http://archive.debian.org/debian $codename main
deb [trusted=yes] http://archive.debian.org/debian-security $codename/updates main
APT
		cat >/etc/apt/apt.conf.d/99-eol-archive <<'APTCONF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
APTCONF
		;;
	debian11)
		# Bullseye main is on archive.debian.org, but the base image already
		# carries security-updated packages that the frozen main suite cannot
		# satisfy, so the live suites are still the working combination.
		#
		# bullseye-security is listed on both mirrors on purpose. They are
		# mid-decommission and currently inconsistent with each other: each
		# serves an index naming pool files the other one has and it does not,
		# so a single mirror 404s part way through an install while the pair
		# lets apt fall back. Drop to one entry once bullseye-security lands on
		# archive.debian.org, which is where this branch should eventually go.
		cat >/etc/apt/sources.list <<'APT'
deb [trusted=yes] http://deb.debian.org/debian bullseye main
deb [trusted=yes] http://security.debian.org/debian-security bullseye-security main
deb [trusted=yes] http://deb.debian.org/debian-security bullseye-security main
APT
		cat >/etc/apt/apt.conf.d/99-eol-archive <<'APTCONF'
Acquire::Retries "3";
APTCONF
		;;
	ubuntu1604 | ubuntu1804 | ubuntu2004)
		# Still served from archive.ubuntu.com while ESM packages remain published.
		;;
	*)
		printf 'unknown EOL distribution id: %s\n' "$distro" >&2
		exit 64
		;;
esac

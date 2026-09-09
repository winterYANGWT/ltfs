#!/bin/sh

set -eu

# EOL distributions stop serving packages from their normal repositories.
# Each case pins an archive location that still works. These archives are
# frozen and receive no security updates, which is the whole reason EOL
# images are limited to the runtime role.
#
# Signature verification stays ON everywhere. What lapses on an EOL archive is
# the Release file's Valid-Until, not the signature, and the signing keys are
# already in the base image -- so the fix is to relax the freshness check
# alone. Turning verification off would also stop apt/dnf noticing a truncated
# or corrupted download, which is the failure these archives are most likely
# to produce.
distro=${1:?usage: configure-eol-repositories DISTRO_ID}

case "$distro" in
	centos7)
		# The key ships in the base image, so enabling gpgcheck adds no new
		# trust source.
		rm -f /etc/yum.repos.d/*.repo
		cat >/etc/yum.repos.d/vault.repo <<'REPO'
[base]
name=CentOS 7.9.2009 vault - base
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS 7.9.2009 vault - updates
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS 7.9.2009 vault - extras
baseurl=https://archive.kernel.org/centos-vault/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
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
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-28-fedora

[updates]
name=Fedora 28 archive - updates
baseurl=${base}/updates/28/Everything/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-28-fedora
REPO
		;;
	debian9 | debian10)
		codename=$([ "$distro" = debian9 ] && echo stretch || echo buster)
		cat >/etc/apt/sources.list <<APT
deb http://archive.debian.org/debian $codename main
deb http://archive.debian.org/debian-security $codename/updates main
APT
		cat >/etc/apt/apt.conf.d/99-eol-archive <<'APTCONF'
Acquire::Check-Valid-Until "false";
APTCONF
		;;
	debian11)
		# snapshot.debian.org, not the live suites: bullseye-security is
		# mid-decommission and its indexes now name pool files that are gone
		# from every mirror, so a live install resolves a dependency and then
		# 404s fetching it. Snapshot is Debian's own frozen archive and still
		# serves them. Frozen bullseye main alone is not an option either --
		# the base image carries security-updated libc6, perl-base and
		# libsepol1 that only the security suite can satisfy.
		#
		# The timestamp is pinned, exactly like a package version: it makes
		# this image reproducible instead of drifting with the live mirrors.
		# It is not derived from the clock. 20260901T000000Z matches what
		# debian:11 ships, so nothing is downgraded.
		#
		# Signature verification stays on; only the Release files' Valid-Until
		# has lapsed, which is what Check-Valid-Until answers.
		cat >/etc/apt/sources.list <<'APT'
deb http://snapshot.debian.org/archive/debian/20260901T000000Z bullseye main
deb http://snapshot.debian.org/archive/debian-security/20260901T000000Z bullseye-security main
APT
		cat >/etc/apt/apt.conf.d/99-eol-archive <<'APTCONF'
Acquire::Check-Valid-Until "false";
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

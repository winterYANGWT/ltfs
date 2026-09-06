# Autotools image internals

Read this before changing anything in `docker/`. For building and using the
images, see [`../README.md`](../README.md).

## Stage graph

Supported distributions (`Dockerfile.apt`, `Dockerfile.rpm`) — one file per
package manager, all three roles:

```text
${BASE_IMAGE} ──▶ ci-base ──┬──▶ ci-validation ──(pass marker only)──┐
                            │                                        │
                            └──▶ ci ◀────────────────────────────────┘
                                  ├──▶ dev
                                  └──▶ runtime-builder ──(staging tree)──┐
${RUNTIME_BASE_IMAGE} ─────────────────────────────▶ runtime ◀───────────┘
```

`ci-validation` copies the source in, compiles it, installs to root, and
smoke-tests it. Only `/tmp/ci-build-self-test` is copied forward, so the
published `ci` image proves a build happened without shipping the source or the
binary. `runtime-builder` builds a second time with the `runtime-file` profile
and stages into `/tmp/ltfs-stage`; `runtime` starts from a clean base and copies
only that tree, which is why no compiler can reach the final image.

EOL distributions (`Dockerfile.apt-eol`, `Dockerfile.rpm-eol`) are runtime only:
`builder` stages a tree, the glibc floor check gates it, and `runtime` starts
from the *same* `${BASE_IMAGE}` so the artifacts keep that release's glibc
floor. There is no `ci` or `dev` — an EOL image exists to run LTFS on an old
host, not to develop on one.

## Why four Dockerfiles

The split is package manager × lifecycle, and nothing else. `apt` and `rpm`
differ in more than package names — repo enablement (`CRB_REPO_NAME`), the
`net-snmp-config` shim, and EPEL for dev — so one file with branches would be
worse than two without. Supported and EOL differ in shape, not detail: EOL has
no `ci`/`dev` stages, adds the glibc floor check, and pins frozen archives.

Distribution differences are data in `docker-bake.hcl`, never branches in a
Dockerfile. Every `FROM` resolves to an `ARG` or a stage in the same file.

## Script contracts

| Script | Input | Result | Notable exits |
| --- | --- | --- | --- |
| `build.sh` | `SOURCE_DIR` `OUTPUT_DIR` `AUTOTOOLS_PROFILE` `JOBS` `CONFIGURE_ARGS` | Staging tree under `OUTPUT_DIR`, plus `.ltfs-autotools-build` | `64` bad profile/JOBS, `66` no source tree, `73` `OUTPUT_DIR` not empty |
| `self-test.sh` | `LTFS_IMAGE_ROLE` and the `LTFS_SELF_TEST_*` switches below | Role checks; prints a pass line | `64` bad switch or role, `66` source required but absent, `77` root required |
| `smoke-test.sh` | `LTFS_PREFIX` `EXPECT_FILE_DEFAULT` `EXPECT_MINIMAL_RUNTIME` `EXPECT_ORDERED_COPY` | Validates an installed tree | `1` on any failed assertion |
| `format-file-backend-test.sh` | `LTFS_PREFIX` | Formats a throwaway virtual tape with `mkltfs` | `1` if no tape files appear |
| `check-glibc-floor.sh` | `$1` stage dir, `LTFS_MAX_GLIBC_SYMBOL` | Rejects ELF objects needing a newer glibc | `64` malformed ceiling, `1` violation or no ELF found |
| `configure-eol-repositories.sh` | `$1` distribution id | Rewrites the package sources | `64` unknown id |
| `runtime-entrypoint.sh` | `LTFS_IMAGE_ROLE` `LTFS_SELF_TEST_ON_START` `LTFS_SELF_TEST_COMMAND` | Dispatches per role | `64` bad role or switch |
| `icu-config` | one option | pkg-config shim for LTFS's legacy ICU probe | `64` unsupported option |
| `net-snmp-config-compat.sh` | any arguments | Normalizes `--cflags` only, forwards everything else | `69` real provider missing |

The `LTFS_SELF_TEST_*` switches are all `0`/`1` and default to `0`:
`BUILD_SOURCE` compiles `SOURCE_DIR`, `REQUIRE_SOURCE` makes a missing source
tree fatal, and `INSTALL_TO_ROOT` installs the result and smoke-tests it — it
requires `BUILD_SOURCE=1` and root. Only `ci-validation` sets them, so running
`self-test` in a shipped image never compiles anything.

Both shims exist because of upstream behaviour, not preference. `icu-config`
answers LTFS's legacy probe on distributions that ship only pkg-config.
`net-snmp-config-compat.sh` shadows the real binary on `PATH` and strips one
compound Fortify token that LTFS's configure cleanup would otherwise leave as a
bare `-Wp`, plus net-snmp's own `-Werror`; every other call is passed through
untouched.

## What each role's self-test checks

`self-test.sh` is shipped in every image and dispatches on `LTFS_IMAGE_ROLE`.
`ci` and `dev` share a branch; `runtime` is separate.

**`ci` and `dev`** check that the toolchain is present and works — `autoconf`,
`automake`, `gcc`, `make`, `libtoolize`, `python`, `tar`, then `icu-config
--version` and `net-snmp-config --cflags` actually executed, because both are
shims whose mere presence proves nothing.

**`dev`** adds `ccache`, `gdb`, `git`, a real `import xattr`, a root check, and
that `/workspace` and `/out` are writable.

**`runtime`** is the substantive one. It runs `smoke-test.sh` with
`EXPECT_FILE_DEFAULT=1 EXPECT_MINIMAL_RUNTIME=1`, which requires `ltfs`,
`mkltfs`, `ltfsck`, and `ltfs_ordered_copy` to exist and answer `--help`;
requires `libtape-file.so` and a `ltfs.conf` declaring file as the default
backend; runs `ldd` over **every** `.so*` under the prefix and fails on any
`not found`; and rejects leftover compilers, headers, pkg-config data, and
libtool archives. Then `format-file-backend-test.sh` formats a real virtual
tape, and the entrypoint is exercised with no arguments and with `--help`.

The `ldd` sweep and the format test are the two checks that have historically
caught real breakage. Note what is *not* covered: `libtape-sg.so` is only
link-checked, never loaded, so the sg path has no automated coverage without a
drive.

## Adding or changing a distribution

Edit the matching list in `docker-bake.hcl` — `APT_DISTRIBUTIONS`,
`RPM_DISTRIBUTIONS`, `EOL_APT_DISTRIBUTIONS`, or `EOL_RPM_DISTRIBUTIONS`. A new
supported entry produces three targets, a new EOL entry produces one runtime.
Runtime library package names are release-specific and must be verified against
the real release, not guessed from the previous one.

Beyond the shared keys, EOL entries carry `max_glibc_symbol`; the APT ones carry
`python_xattr_package` (Xenial needs `python3-pyxattr`), and the RPM ones carry
`pyxattr_via_pip`, `extra_build_packages`, and `extra_runtime_packages`.

## EOL specifics

The glibc floor is the point of these images. `check-glibc-floor.sh` reads the
highest `GLIBC_` symbol version each staged ELF object requires and fails the
build if it exceeds the ceiling. Without it an EOL image would build cleanly and
still be unusable on the host it was built for.

Frozen archives move. Current pinning, all of it time-sensitive:

- **CentOS 7** — `archive.kernel.org/centos-vault`, because `vault.centos.org`
  was not serving usable metadata when this was written.
- **Fedora 28** — the Fedora archive, with `Everything/` in both paths.
- **Debian 9/10** — `archive.debian.org`, with `Check-Valid-Until` disabled.
- **Debian 11** — still the live suites, and `bullseye-security` is listed on
  *two* mirrors on purpose: they are mid-decommission and each serves an index
  naming pool files the other has, so one mirror alone 404s part way through an
  install. Collapse this to a single `archive.debian.org` entry once
  bullseye-security lands there.
- **Ubuntu 16.04/18.04/20.04** — no rewrite; `archive.ubuntu.com` still serves
  them while ESM packages remain published.
- **Rocky 8/9 dev** — `ccache` comes from an immutable Koji URL because live
  EPEL metadata no longer lists the retired build. Rocky 10 uses plain EPEL.

The RPM base images ship `binutils`, so CentOS 7 and Rocky 8/9/10 runtimes
contain `/usr/bin/ld` and `/usr/bin/as`. That is accepted, not overlooked:
removing it frees nothing (the content is in the base layer, so `rpm -e` only
writes whiteouts and measurably *grew* the images by ~6 MB) and a linker without
a compiler builds nothing.

## Invariants

A change that breaks one of these should be treated as wrong until argued
otherwise:

- **Six scripts are frozen** — `build.sh`, `self-test.sh`, `smoke-test.sh`,
  `format-file-backend-test.sh`, `runtime-entrypoint.sh`, `icu-config`. Adapt
  through Bake data, Dockerfile arguments, or the EOL repository script instead.
- **No date-driven lifecycle.** Nothing here may age a distribution out on a
  timer; lifecycle moves happen in an explicit pull request.
- **`FROM` takes an `ARG` or a stage in the same file.** No hardcoded base image.
- **No `test-*` shadow targets, and the six groups stay six.**
- **Runtime cannot compile.** Each runtime stage asserts at build time that
  `gcc cc c++ g++ make autoconf automake libtoolize` are unreachable, so a base
  image reinstating a toolchain fails the build. `ld`/`as` are an accepted
  exception; see the EOL section above.
- **Every image records its source revision.** `SOURCE_REVISION` comes from the
  Bake `REVISION` variable; CI passes the commit SHA.
- **Every stage sets `LANG`.** `ltfs`, `ltfsck`, and `mkltfs` set it themselves
  when unset, but only after writing `LTFS9015W` to stderr, which then leads
  every invocation's output.
- **Complexity budget.** `find docker -type f | xargs wc -l` stays under 2400,
  with 2200 as the line at which to stop and reconsider the design.

## Local checks

```sh
bash docker/autotools/tests/test-image-entrypoint.sh
bash -n docker/autotools/scripts/*.sh docker/autotools/tests/*.sh
sh -n docker/autotools/scripts/icu-config
docker buildx bake -f docker/docker-bake.hcl --check
docker buildx bake -f docker/docker-bake.hcl all --print
```

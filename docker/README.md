# LTFS container images

One Bake definition builds LTFS for 16 distributions in two roles — 24 targets
in total. `linux/amd64` only.

Use these images to build LTFS reproducibly on a distribution you do not run, to
get an interactive debugging environment, or to run LTFS against a tape drive
without installing a toolchain on the host.

## Quick start

```sh
# The 16 supported targets
docker buildx bake -f docker/docker-bake.hcl

# One target, loaded into the local daemon
docker buildx bake -f docker/docker-bake.hcl runtime-debian13 --load

# Ask an image to re-run its own checks
docker run --rm ltfs-autotools:local-debian13-runtime self-test
```

A target that builds has already tested itself: the supported CI chain compiles
the current source in a throwaway stage and smoke-tests it, runtime targets
format a virtual tape through the file backend, and EOL builders additionally
refuse artifacts that need a newer glibc than the target release provides.

## Image matrix

Supported distributions produce both roles:

| Distribution | `dev` | `runtime` |
| --- | :---: | :---: |
| `ubuntu2604` `ubuntu2404` `ubuntu2204` | ✓ | ✓ |
| `debian13` `debian12` | ✓ | ✓ |
| `rocky10` `rocky9` `rocky8` | ✓ | ✓ |

EOL distributions produce `runtime` only, each with a glibc ceiling enforced at
build time:

| Distribution | Base image | glibc ceiling |
| --- | --- | --- |
| `debian11` | `debian:11` | 2.31 |
| `ubuntu2004` | `ubuntu:20.04` | 2.31 |
| `debian10` | `debian:10` | 2.28 |
| `ubuntu1804` | `ubuntu:18.04` | 2.27 |
| `debian9` | `debian:9` | 2.24 |
| `ubuntu1604` | `ubuntu:16.04` | 2.23 |
| `centos7` | `centos:centos7` | 2.17 |
| `fedora28` | `fedora:28` | 2.27 |

> EOL base systems and their frozen archives receive no security updates. They
> exist for deployments that must match an old userspace, kernel, or Docker, and
> are built from a clone rather than published — see
> [Publishing policy](#publishing-policy). Pushing one to a public registry
> requires a product owner explicitly accepting that risk.

## Roles

| Role | Contents | Default command |
| --- | --- | --- |
| `dev` | Full Autotools toolchain plus gdb, ccache, strace, git; compiles a mounted source tree into `/out`; runs as root | `/bin/bash` |
| `runtime` | No toolchain; sg, file, and itdtimg backends, file by default | `ltfs --help` |

`dev` ships no installed `ltfs`: the source tree and its build products live only
in a disposable stage, so the image carries a pass marker naming the source
revision rather than a binary. Build one with `ltfs-autotools-build`.

## Tags, variables, and groups

Tags are `<REGISTRY>/<IMAGE_NAMESPACE>/ltfs-autotools:<VERSION>-<distribution>-<role>`,
which with the defaults below is `ltfs-autotools:local-debian13-dev`.

| Variable | Default | Effect |
| --- | --- | --- |
| `VERSION` | `local` | First tag component |
| `REVISION` | `local` | Any other value adds an immutable `sha-<REVISION>-…` alias tag |
| `REGISTRY` | `docker.io` | Registry host |
| `IMAGE_NAMESPACE` | `library` | Namespace under the registry |

Five groups are the stable entry points — `default` (all supported), `dev`,
`runtime`, `eol`, and `all`. `default` never contains an EOL target, which is
what keeps EOL images out of pull-request builds.

```sh
docker buildx bake -f docker/docker-bake.hcl all
docker buildx bake -f docker/docker-bake.hcl eol
docker buildx bake -f docker/docker-bake.hcl default \
  --set '*.output=type=cacheonly' --progress=plain
```

## Using the Dev image

Interactively — it drops you in a shell with the source mounted:

```sh
docker run --rm -it \
  --mount type=bind,src="$PWD",dst=/workspace \
  ltfs-autotools:local-debian13-dev
```

Or non-interactively, for a build in CI. Mount the source read-only and give it
an empty `/out` for the staging tree:

```sh
mkdir -p .artifacts/debian13
docker run --rm \
  --mount type=bind,src="$PWD",dst=/workspace,readonly \
  --mount type=bind,src="$PWD/.artifacts/debian13",dst=/out \
  ltfs-autotools:local-debian13-dev ltfs-autotools-build
```

The command name is spelled out because `dev` defaults to an interactive shell,
so something has to be passed for a non-interactive build.

`AUTOTOOLS_PROFILE=default|strict|runtime-file`, `JOBS`, `CONFIGURE_ARGS`,
`SOURCE_DIR`, and `OUTPUT_DIR` are the knobs. `OUTPUT_DIR` must be empty so
artifacts from different builds cannot mix. Rocky 8 and 9 default to `strict`;
Rocky 10 uses `default` pending an upstream `_FORTIFY_SOURCE` fix.

Dev runs as root so FUSE and device debugging work, but adds no `--privileged`
of its own. Files it creates in a bind mount may end up root-owned on the host;
build into the container filesystem or a named volume to avoid that.

## Using the Runtime image

```sh
# Format a directory-backed virtual tape
mkdir -p tape-data/tape
docker run --rm \
  --mount type=bind,src="$PWD/tape-data",dst=/var/lib/ltfs \
  ltfs-autotools:local-debian13-runtime \
  mkltfs --device=/var/lib/ltfs/tape \
    --force --tape-serial=TEST01 --volume-name=DOCKERTEST
```

A real mount needs the host's `/dev/fuse`:

```sh
mkdir -p ltfs-mount
docker run --rm -it \
  --device /dev/fuse --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  --mount type=bind,src="$PWD/tape-data",dst=/var/lib/ltfs \
  --mount type=bind,src="$PWD/ltfs-mount",dst=/mnt/ltfs,bind-propagation=rshared \
  ltfs-autotools:local-debian13-runtime \
  ltfs /mnt/ltfs -o tape_backend=file -o devname=/var/lib/ltfs/tape
```

Try dropping `apparmor=unconfined` first and widen only on an actual host error.
For a real drive, add `--device /dev/sg3` to the same command and select the sg
backend with `-o tape_backend=sg -o devname=/dev/sg3`. `lin_tape` and the IBM
proprietary drivers are host kernel components, in no image.

## Running on an old host

A container brings its own userspace and shares only the host kernel, so a
modern runtime often works on an old host. Three things still gate it:

| Gate | Requirement | Note |
| --- | --- | --- |
| Host kernel | Meets the minimum the image's glibc needs | Very old kernels need the matching EOL image |
| Docker | 20.10.10 or newer recommended | Older seccomp profiles can block glibc's `clone3()` fallback |
| Devices | `/dev/fuse`, `/dev/sg*` | Host-provided; pass through with `--device` |

`--security-opt seccomp=unconfined` works around old Docker at the cost of a
wider permission surface. Binaries compiled inside a modern image cannot simply
be copied onto an old host either — that is exactly why EOL runtimes build on
their own release.

## CI and publishing

`.github/workflows/autotools-images.yml` derives its distribution list from the
bake groups, then fans out one job per distribution. The `supported` jobs run on
every push and pull request, on a weekly schedule, and on manual dispatch; the
`eol` jobs run only on schedule, manual dispatch, and `v*` tags. Every job
outputs `cacheonly` into a per-distribution cache scope, so they validate
without publishing.

Publishing supported images means adding a registry login, `packages: write`,
and `push: true`.

### Publishing policy

An image is published only while its distribution is in upstream support.

| Situation | What happens |
| --- | --- |
| Distribution is in support | Published, and refreshed by every build |
| Distribution reaches EOL | Refreshes stop; tags already published stay as they are |
| Distribution was already EOL when added here | Never published |

Three consequences worth stating plainly:

- **EOL images are a build-it-yourself option, not a product.** Clone the
  repository and run `docker buildx bake -f docker/docker-bake.hcl eol` to get
  one for your own use. They install from frozen third-party archives with
  signature verification relaxed or off, so whoever builds one is the one
  accepting that supply chain. That decision does not belong baked into an
  artifact handed to someone else.
- **Published tags are frozen, not withdrawn.** A tag someone already pinned
  keeps working; it simply stops receiving new content, exactly like the
  distribution it was built from. Withdrawing it would break consumers without
  making anyone safer.
- **The transition is a deliberate edit, never a date.** Moving a distribution
  from `APT_DISTRIBUTIONS` / `RPM_DISTRIBUTIONS` to the matching `EOL_*` list in
  `docker-bake.hcl` does all three things at once: it leaves the published
  groups, it drops to `runtime` only, and it switches to archive repositories.
  Nothing here computes a lifecycle from the clock — see the invariants in
  [`autotools/README.md`](autotools/README.md).

Adding a newly released distribution is the same edit in reverse, and is
expected to happen more often than retirement.

## Changing anything here

Read [`autotools/README.md`](autotools/README.md) first. It documents the stage
graph, the contract of each script, what each role's self-test actually checks,
and the invariants a change must not break.

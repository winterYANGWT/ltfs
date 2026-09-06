# LTFS Autotools container images.
#
#   docker buildx bake -f docker/docker-bake.hcl                    # supported images
#   docker buildx bake -f docker/docker-bake.hcl all                # supported and EOL
#   docker buildx bake -f docker/docker-bake.hcl runtime --load     # supported runtimes
#   docker buildx bake -f docker/docker-bake.hcl ci-debian13 --load # one image
#
# Tag schema: ltfs-autotools:<VERSION>-<distribution>-<role>

variable "REGISTRY" {
  default = "docker.io"
}

variable "IMAGE_NAMESPACE" {
  default = "library"
}

variable "VERSION" {
  default = "local"
}

# Set to a 12-character commit SHA when publishing to also emit an immutable alias tag.
variable "REVISION" {
  default = "local"
}

# Supported distributions produce all three roles. Distribution-specific
# package names and repository names are data here, never Dockerfile branches.
variable "APT_DISTRIBUTIONS" {
  default = [
    {
      id               = "ubuntu2604"
      title            = "Ubuntu 26.04"
      base_image       = "ubuntu:26.04"
      runtime_base     = "ubuntu:26.04"
      runtime_packages = "fuse3 libfuse2t64 libicu78 libxml2-16"
    },
    {
      id               = "ubuntu2404"
      title            = "Ubuntu 24.04"
      base_image       = "ubuntu:24.04"
      runtime_base     = "ubuntu:24.04"
      runtime_packages = "fuse libfuse2t64 libicu74 libxml2"
    },
    {
      id               = "ubuntu2204"
      title            = "Ubuntu 22.04"
      base_image       = "ubuntu:22.04"
      runtime_base     = "ubuntu:22.04"
      runtime_packages = "fuse libfuse2 libicu70 libxml2"
    },
    {
      id               = "debian13"
      title            = "Debian 13"
      base_image       = "debian:13"
      runtime_base     = "debian:13-slim"
      runtime_packages = "fuse3 libfuse2t64 libicu76 libxml2"
    },
    {
      id               = "debian12"
      title            = "Debian 12"
      base_image       = "debian:12"
      runtime_base     = "debian:12-slim"
      runtime_packages = "fuse libfuse2 libicu72 libxml2"
    },
  ]
}

variable "RPM_DISTRIBUTIONS" {
  default = [
    # Dev images enable EPEL. Rocky 8 and 9 pin their retired EPEL ccache
    # builds by immutable Koji URL because live EPEL metadata omits them.
    {
      id                 = "rocky10"
      title              = "Rocky Linux 10"
      base_image         = "rockylinux/rockylinux:10"
      runtime_packages   = "fuse-libs libicu libuuid libxml2"
      crb_repo_name      = "crb"
      profile            = "default"
      dev_ccache_package = "ccache"
    },
    {
      id                 = "rocky9"
      title              = "Rocky Linux 9"
      base_image         = "rockylinux/rockylinux:9"
      runtime_packages   = "fuse-libs libicu libuuid libxml2"
      crb_repo_name      = "crb"
      profile            = "strict"
      dev_ccache_package = "https://kojipkgs.fedoraproject.org/packages/ccache/4.5.1/2.el9/x86_64/ccache-4.5.1-2.el9.x86_64.rpm"
    },
    {
      id                 = "rocky8"
      title              = "Rocky Linux 8"
      base_image         = "rockylinux/rockylinux:8"
      runtime_packages   = "fuse-libs libicu libuuid libxml2"
      crb_repo_name      = "powertools"
      profile            = "strict"
      dev_ccache_package = "https://kojipkgs.fedoraproject.org/packages/ccache/3.7.7/1.el8/x86_64/ccache-3.7.7-1.el8.x86_64.rpm"
    },
  ]
}

# EOL distributions intentionally produce Runtime only. Their frozen package
# archives no longer receive security fixes and are excluded from the default group.
variable "EOL_APT_DISTRIBUTIONS" {
  default = [
    {
      id               = "debian11"
      title            = "Debian 11"
      base_image       = "debian:11"
      runtime_packages = "fuse libfuse2 libicu67 libxml2"
      max_glibc_symbol = "2.31"
      python_xattr_package = "python3-xattr"
    },
    {
      id               = "ubuntu2004"
      title            = "Ubuntu 20.04"
      base_image       = "ubuntu:20.04"
      runtime_packages = "fuse libfuse2 libicu66 libxml2"
      max_glibc_symbol = "2.31"
      python_xattr_package = "python3-xattr"
    },
    {
      id               = "debian10"
      title            = "Debian 10"
      base_image       = "debian:10"
      runtime_packages = "fuse libfuse2 libicu63 libxml2"
      max_glibc_symbol = "2.28"
      python_xattr_package = "python3-xattr"
    },
    {
      id               = "ubuntu1804"
      title            = "Ubuntu 18.04"
      base_image       = "ubuntu:18.04"
      runtime_packages = "fuse libfuse2 libicu60 libxml2"
      max_glibc_symbol = "2.27"
      python_xattr_package = "python3-xattr"
    },
    {
      id               = "debian9"
      title            = "Debian 9"
      base_image       = "debian:9"
      runtime_packages = "fuse libfuse2 libicu57 libxml2"
      max_glibc_symbol = "2.24"
      python_xattr_package = "python3-xattr"
    },
    {
      id               = "ubuntu1604"
      title            = "Ubuntu 16.04"
      base_image       = "ubuntu:16.04"
      runtime_packages = "fuse libfuse2 libicu55 libxml2"
      max_glibc_symbol = "2.23"
      python_xattr_package = "python3-pyxattr"
    },
  ]
}

variable "EOL_RPM_DISTRIBUTIONS" {
  default = [
    {
      id                     = "centos7"
      title                  = "CentOS 7"
      base_image             = "centos:centos7"
      runtime_packages       = "fuse-libs libicu libuuid libxml2"
      max_glibc_symbol       = "2.17"
      pyxattr_via_pip        = "1"
      extra_build_packages   = ""
      extra_runtime_packages = ""
    },
    {
      id                     = "fedora28"
      title                  = "Fedora 28"
      base_image             = "fedora:28"
      runtime_packages       = "fuse-libs libicu libuuid libxml2"
      max_glibc_symbol       = "2.27"
      pyxattr_via_pip        = "0"
      extra_build_packages   = ""
      extra_runtime_packages = "python3-pyxattr"
    },
  ]
}

function "tags" {
  params = [distribution, role]
  result = REVISION == "local" ? [
    "${REGISTRY}/${IMAGE_NAMESPACE}/ltfs-autotools:${VERSION}-${distribution}-${role}",
    ] : [
    "${REGISTRY}/${IMAGE_NAMESPACE}/ltfs-autotools:${VERSION}-${distribution}-${role}",
    "${REGISTRY}/${IMAGE_NAMESPACE}/ltfs-autotools:sha-${REVISION}-${distribution}-${role}",
  ]
}

# Six stable entry points. EOL images never enter the default PR/push build.
group "default" {
  targets = ["ci", "dev", "runtime"]
}

group "ci" {
  targets = [
    "ci-ubuntu2604",
    "ci-ubuntu2404",
    "ci-ubuntu2204",
    "ci-debian13",
    "ci-debian12",
    "ci-rocky10",
    "ci-rocky9",
    "ci-rocky8",
  ]
}

group "dev" {
  targets = [
    "dev-ubuntu2604",
    "dev-ubuntu2404",
    "dev-ubuntu2204",
    "dev-debian13",
    "dev-debian12",
    "dev-rocky10",
    "dev-rocky9",
    "dev-rocky8",
  ]
}

group "runtime" {
  targets = [
    "runtime-ubuntu2604",
    "runtime-ubuntu2404",
    "runtime-ubuntu2204",
    "runtime-debian13",
    "runtime-debian12",
    "runtime-rocky10",
    "runtime-rocky9",
    "runtime-rocky8",
  ]
}

group "eol" {
  targets = [
    "runtime-debian11",
    "runtime-ubuntu2004",
    "runtime-centos7",
    "runtime-debian10",
    "runtime-ubuntu1804",
    "runtime-debian9",
    "runtime-ubuntu1604",
    "runtime-fedora28",
  ]
}

group "all" {
  targets = ["default", "eol"]
}

target "_common" {
  context   = "."
  platforms = ["linux/amd64"]
  # .git is out of the build context, so the revision is passed in.
  args = {
    SOURCE_REVISION = REVISION
  }
  labels = {
    "org.opencontainers.image.source"   = "https://github.com/LinearTapeFileSystem/ltfs"
    "org.opencontainers.image.version"  = VERSION
    "org.opencontainers.image.revision" = REVISION
    "org.opencontainers.image.licenses" = "BSD-3-Clause"
    "io.ltfs.build.system"              = "autotools"
  }
}

target "ci-apt" {
  matrix     = { distribution = APT_DISTRIBUTIONS }
  name       = "ci-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.apt"
  target     = "ci"
  args = {
    BASE_IMAGE = distribution.base_image
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS CI - ${distribution.title}"
    "org.opencontainers.image.description" = "LTFS Autotools CI toolchain for ${distribution.title}"
    "io.ltfs.image.role"                   = "ci"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
  }
  tags = tags(distribution.id, "ci")
}

target "dev-apt" {
  matrix     = { distribution = APT_DISTRIBUTIONS }
  name       = "dev-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.apt"
  target     = "dev"
  args = {
    BASE_IMAGE = distribution.base_image
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS Dev - ${distribution.title}"
    "org.opencontainers.image.description" = "Interactive LTFS Autotools development environment for ${distribution.title}"
    "io.ltfs.image.role"                   = "dev"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
  }
  tags = tags(distribution.id, "dev")
}

target "runtime-apt" {
  matrix     = { distribution = APT_DISTRIBUTIONS }
  name       = "runtime-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.apt"
  target     = "runtime"
  args = {
    BASE_IMAGE         = distribution.base_image
    RUNTIME_BASE_IMAGE = distribution.runtime_base
    RUNTIME_PACKAGES   = distribution.runtime_packages
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS Runtime - ${distribution.title}"
    "org.opencontainers.image.description" = "Minimal LTFS runtime; file backend by default"
    "io.ltfs.image.role"                   = "runtime"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
    "io.ltfs.runtime.default-backend"      = "file"
  }
  tags = tags(distribution.id, "runtime")
}

target "ci-rpm" {
  matrix     = { distribution = RPM_DISTRIBUTIONS }
  name       = "ci-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.rpm"
  target     = "ci"
  args = {
    AUTOTOOLS_PROFILE = distribution.profile
    BASE_IMAGE        = distribution.base_image
    CRB_REPO_NAME     = distribution.crb_repo_name
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS CI - ${distribution.title}"
    "org.opencontainers.image.description" = "LTFS Autotools CI toolchain for ${distribution.title}"
    "io.ltfs.image.role"                   = "ci"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
  }
  tags = tags(distribution.id, "ci")
}

target "dev-rpm" {
  matrix     = { distribution = RPM_DISTRIBUTIONS }
  name       = "dev-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.rpm"
  target     = "dev"
  args = {
    AUTOTOOLS_PROFILE  = distribution.profile
    BASE_IMAGE         = distribution.base_image
    CRB_REPO_NAME      = distribution.crb_repo_name
    DEV_CCACHE_PACKAGE = distribution.dev_ccache_package
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS Dev - ${distribution.title}"
    "org.opencontainers.image.description" = "Interactive LTFS Autotools development environment for ${distribution.title}"
    "io.ltfs.image.role"                   = "dev"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
  }
  tags = tags(distribution.id, "dev")
}

target "runtime-rpm" {
  matrix     = { distribution = RPM_DISTRIBUTIONS }
  name       = "runtime-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.rpm"
  target     = "runtime"
  args = {
    AUTOTOOLS_PROFILE = distribution.profile
    BASE_IMAGE        = distribution.base_image
    CRB_REPO_NAME     = distribution.crb_repo_name
    RUNTIME_PACKAGES  = distribution.runtime_packages
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS Runtime - ${distribution.title}"
    "org.opencontainers.image.description" = "Minimal LTFS runtime; file backend by default"
    "io.ltfs.image.role"                   = "runtime"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "supported"
    "io.ltfs.runtime.default-backend"      = "file"
  }
  tags = tags(distribution.id, "runtime")
}

target "runtime-eol-apt" {
  matrix     = { distribution = EOL_APT_DISTRIBUTIONS }
  name       = "runtime-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.apt-eol"
  target     = "runtime"
  args = {
    BASE_IMAGE            = distribution.base_image
    DISTRO_ID             = distribution.id
    LTFS_MAX_GLIBC_SYMBOL = distribution.max_glibc_symbol
    PYTHON_XATTR_PACKAGE  = distribution.python_xattr_package
    RUNTIME_PACKAGES      = distribution.runtime_packages
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS EOL Runtime - ${distribution.title}"
    "org.opencontainers.image.description" = "LTFS runtime for an EOL base OS; file backend by default"
    "io.ltfs.image.role"                   = "runtime"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "eol"
    "io.ltfs.eol.notice"                   = "base OS receives no security updates"
    "io.ltfs.runtime.default-backend"      = "file"
  }
  tags = tags(distribution.id, "runtime")
}

target "runtime-eol-rpm" {
  matrix     = { distribution = EOL_RPM_DISTRIBUTIONS }
  name       = "runtime-${distribution.id}"
  inherits   = ["_common"]
  dockerfile = "docker/autotools/Dockerfile.rpm-eol"
  target     = "runtime"
  args = {
    BASE_IMAGE             = distribution.base_image
    DISTRO_ID              = distribution.id
    EXTRA_BUILD_PACKAGES   = distribution.extra_build_packages
    EXTRA_RUNTIME_PACKAGES = distribution.extra_runtime_packages
    LTFS_MAX_GLIBC_SYMBOL  = distribution.max_glibc_symbol
    PYXATTR_VIA_PIP        = distribution.pyxattr_via_pip
    RUNTIME_PACKAGES       = distribution.runtime_packages
  }
  labels = {
    "org.opencontainers.image.title"       = "LTFS EOL Runtime - ${distribution.title}"
    "org.opencontainers.image.description" = "LTFS runtime for an EOL base OS; file backend by default"
    "io.ltfs.image.role"                   = "runtime"
    "io.ltfs.image.distribution"           = distribution.id
    "io.ltfs.distribution.lifecycle"       = "eol"
    "io.ltfs.eol.notice"                   = "base OS receives no security updates"
    "io.ltfs.runtime.default-backend"      = "file"
  }
  tags = tags(distribution.id, "runtime")
}

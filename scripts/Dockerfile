# syntax=docker/dockerfile:1.7
# macOS builder image for ImmortalWrt/OpenWrt.
FROM ubuntu:22.04

ARG TARGETARCH
ARG GO_BOOTSTRAP_VERSION=1.26.2

ENV DEBIAN_FRONTEND=noninteractive
ENV FORCE_UNSAFE_CONFIGURE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
	rm -f /etc/apt/apt.conf.d/docker-clean \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ack antlr3 asciidoc autoconf automake autopoint \
		binutils bison build-essential bzip2 ca-certificates ccache clang cmake cpio curl \
		device-tree-compiler ecj fastjar file flex g++ gawk gettext git \
		gperf haveged help2man intltool libelf-dev libgnutls28-dev \
		libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev \
		libpython3-dev libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm \
		lrzsz mkisofs msmtp nano ninja-build p7zip p7zip-full patch perl pkgconf \
		python3 python3-dev python3-distutils python3-pip python3-ply python3-docutils \
		python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig \
		texinfo time uglifyjs unzip vim wget xmlto xxd xsltproc zlib1g-dev zstd

RUN case "${TARGETARCH}" in \
		amd64|arm64) go_arch="${TARGETARCH}" ;; \
		*) echo "unsupported Docker TARGETARCH for Go bootstrap: ${TARGETARCH}" >&2; exit 1 ;; \
	esac \
	&& curl -fsSL "https://go.dev/dl/go${GO_BOOTSTRAP_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go-bootstrap.tar.gz \
	&& rm -rf /usr/local/go \
	&& tar -C /usr/local -xzf /tmp/go-bootstrap.tar.gz \
	&& rm -f /tmp/go-bootstrap.tar.gz \
	&& /usr/local/go/bin/go version

WORKDIR /work

CMD ["/bin/bash", "/scripts/build-inner.sh"]

# macOS builder image for ImmortalWrt/OpenWrt.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FORCE_UNSAFE_CONFIGURE=1

RUN apt-get update \
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
		texinfo time uglifyjs unzip vim wget xmlto xxd xsltproc zlib1g-dev zstd \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /work

CMD ["/bin/bash", "/scripts/build-inner.sh"]

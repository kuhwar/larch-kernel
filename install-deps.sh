#!/bin/sh
# install-deps.sh — install what build-kernel.sh needs on Debian trixie (as root):
# Debian's patched kernel source and its amd64 config, plus the toolchain.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    linux-source-6.12 \
    linux-config-6.12 \
    build-essential \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    openssl \
    kmod \
    cpio \
    rsync \
    xz-utils \
    debhelper \
    ca-certificates

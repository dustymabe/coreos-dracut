#!/bin/bash
# module-setup for coreos

# called by dracut
check() {
    return 0
    require_binaries curl || return 1
    require_binaries bzip2 || return 1
    return 255
}

# called by dracut
depends() {
    echo network url-lib
    return 0
}

# called by dracut
install() {
    inst_multiple bzip2
    inst_multiple cut
    inst_multiple lsof
    inst_multiple diff
    inst_multiple cmp
    inst_multiple dc
    inst_multiple lsblk
    inst_multiple tee
    inst_multiple df
    inst_multiple free
    inst_multiple gunzip
    inst_multiple zcat
    inst_multiple head
#   inst_multiple gpg
    inst_multiple curl
    inst_multiple md5sum
    inst_multiple mktemp
    inst_multiple wipefs
    inst_multiple mkfs
    inst_multiple blockdev
    inst_multiple dd
    inst_multiple awk
    inst_multiple pidof
    inst_multiple sha256sum
    inst_simple "$moddir/coreos-installer.sh" /usr/bin/coreos-installer.sh
    inst_simple "$moddir/coreos-install.service" "${systemdsystemunitdir}/coreos-install.service"
    inst_hook cmdline 90 "$moddir/parse-coreos.sh"
    mkdir -p "${initdir}${systemdsystemconfdir}/initrd.target.wants"
    ln_r "${systemdsystemunitdir}/coreos-install.service"\
        "${systemdsystemconfdir}/initrd.target.wants/coreos-install.service"
}


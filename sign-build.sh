#!/bin/bash

if [[ $# -lt 1 ]]; then
    echo "$0 PKGNAME-VERSION-RELEASE"
    exit 1
fi

function trap_exit {
    cd /tmp
    rm -rf ${TMPDIR}
}

trap trap_exit EXIT

TMPDIR=$(mktemp -d) 
cd ${TMPDIR} 
for pkg in "$@"; do
    koji download-build --debuginfo ${pkg}
done
rpmsign --addsign --key-id=abec1471 *.rpm 
koji import-sig *.rpm

#!/bin/bash

KOJI_WHOAMI=$(koji moshimoshi | head -1 | cut -d ',' -f2 | tr -d '!' | tr -d ' ')

TARGET=''
PACKAGE=''
COMMIT='HEAD'
OWNER=${KOJI_WHOAMI}

REPOBASE='git+https://github.com/fermilab-context-rpms'

#############################################################
#############################################################
usage () {
    echo "${0} -t stream8 -p mypkg <-c commit> <-o owner>"    2>&1
    echo ""                                                   2>&1
    echo " -t is the koji build target"                       2>&1
    echo " -p is the package to build"                        2>&1
    echo "    if you pass a full url 'git+http://xxxxx/'"     2>&1
    echo "    it will be used as is, otherwise you'll get"    2>&1
    echo "    the repo from '${REPOBASE}'"                    2>&1
    echo " -c the commit to build, defaults to '${COMMIT}'"   2>&1
    echo " -o the owner of unknown packages in koji"          2>&1
    echo "    default is '${OWNER}'"                          2>&1
    echo ""                                                   2>&1
    exit 1
}

#############################################################
# setup args in the right order for making getopt evaluation
# nice and easy.  You'll need to read the manpages for more info
args=$(getopt -o ht:p:c:o: -- "$@")
eval set -- "$args"

for arg in $@; do
    case $1 in
        -- )
            # end of getopt args, shift off the -- and get out of the loop
            shift
            break 2
           ;;
         -t )
            # Build Target
            TARGET=$2
            shift 2
           ;;
         -p )
            # Package to build
            PACKAGE=$2
            shift 2
           ;;
         -c )
            # Commit to build against
            COMMIT=$2
            shift 2
           ;;
         -o )
            # Package owner (if unset)
            OWNER=$2
            shift 2
           ;;
         -h )
            # get help
            usage
            shift
           ;;
    esac
done
#############################################################

if [[ "x${TARGET}" == 'x' ]]; then
    usage
elif [[ "x${PACKAGE}" == 'x' ]]; then
    usage
fi

PKG_BASENAME=$(basename ${PACKAGE} | sed -e 's/\.git$//')

TARGET_PACKAGE_TAG=$(koji list-targets | grep "^${TARGET} " | awk '{print $3}')
if [[ "x${TARGET_PACKAGE_TAG}" == 'x' ]]; then
    echo "${TARGET} not found in koji targets"     2>&1
    echo "koji list-targets | grep '^${TARGET} '"  2>&1
    exit 1
fi

# Set package ownership
koji add-pkg --owner=${OWNER} ${TARGET_PACKAGE_TAG} ${PKG_BASENAME} >/dev/null
if [[ $? -ne 0 ]]; then
    koji add-pkg --owner=${OWNER} ${TARGET_PACKAGE_TAG} ${PKG_BASENAME}
    exit 1
fi
RELEASE_PACKAGE_TAG=$(echo ${TARGET_PACKAGE_TAG} | sed -e 's/TESTING/RELEASE/')
koji add-pkg --owner=${OWNER} ${RELEASE_PACKAGE_TAG} ${PKG_BASENAME} >/dev/null
if [[ $? -ne 0 ]]; then
    koji add-pkg --owner=${OWNER} ${RELEASE_PACKAGE_TAG} ${PKG_BASENAME}
    exit 1
fi

echo ${PACKAGE} | grep -q '^git'
if [[ $? -ne 0 ]]; then
    PACKAGE="${REPOBASE}/${PACKAGE}"
fi

koji build ${TARGET} "${PACKAGE}#${COMMIT}"

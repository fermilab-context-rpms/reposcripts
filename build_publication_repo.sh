#!/bin/bash -u

#############################################################
### CONFIG SHOULD CONTAIN DEFINED VERSIONS OF:
###   WITH THE CORRECT VALUES FOR YOUR REPO
#############################################################
#IS_TESTING_REPO="FALSE"

#CHOWN_AS=
#KOJI_TAG=
#REPO_KEY_ID=
#DIST_REPO_SYNC_SOURCE=
#DIST_REPO_SYNC_TARGET=

### NON-TESTING TARGETS ALSO REQUIRE:
### IF SET TO EMPTY STRING, THESE ARE SKIPPED
#YUM_GROUPS_FILENAME=

#REPO_KEY_SOURCE_FILENAME=
#REPO_KEY_TARGET_FILENAME=

#RELEASE_NOTES_SOURCE_ADOC_FILENAME=
#RELEASE_NOTES_OUTPUT_HTML_FILENAME=

#INITIAL_REPO_RPM=
#INITIAL_AUTOMATION_RPM=


#############################################################
#############################################################
usage () {
    echo "${0} -c conf.d/el/stream8/release.conf"    2>&1
    exit 1
}

newest_rpm() {
    if [[ $# -ne 2 ]]; then
        echo "newest_rpm rpm1 rpm2"                                           >&2
        echo '  pass in two rpms, returns name of newest rpm'                 >&2
        echo '  DOES NOT check if the two rpms should be compared'            >&2
        echo ' Example:'                                                      >&2
        echo ' NEWEST=$(newest_rpm tz-2-1.el6.i686.rpm tz-2-2.el6.i686.rpm)'  >&2
        echo ' NEWEST is tz-2-2.el6.i686.rpm'                                 >&2
        exit 1
    fi

    EVRA=$(rpm -qp --qf "%{EPOCH}:%{VERSION}-%{RELEASE}" "${1}" | sed -e 's/(none)/0/')
    EVRB=$(rpm -qp --qf "%{EPOCH}:%{VERSION}-%{RELEASE}" "${2}" | sed -e 's/(none)/0/')

    if [[ "x${EVRA}" == 'x' || "x${EVRB}" == 'x' ]]; then
        echo "Failure to read rpm"  >&2
        exit 1
    fi

    OUT=$(rpmdev-vercmp ${EVRA} ${EVRB} 2>&1)
    RC=$?
    if [[ ${RC} -eq 0 ]]; then
        echo ${1}
        return
    elif [[ ${RC} -eq 11 ]]; then
        echo ${1}
        return
    elif [[ ${RC} -eq 12 ]]; then
        echo ${2}
        return
    else
        echo "rpmdev-vercmp ${EVRA} ${EVRB}" >&2
        echo "Unknown return code ${RC}"     >&2
        echo "OUTPUT: ${OUT}"                >&2
        exit 1
    fi
}

newest_rpm_from_list() {
    if [[ $# -eq 0 ]]; then
        echo 'newest_rpm_from_list rpm1 rpm2 rpm3 rpm4'      >&2
        echo ' pass in as many as you like, but at least 1'  >&2
        exit 1
    elif [[ $# -eq 1 ]]; then
        echo ${1}
        return 0
    fi

    NEWEST_RPM="${1}"
    for thisrpm in "$@"; do
        # NEWEST_RPM will have the filename of the actually newest RPM
        NEWEST_RPM=$(newest_rpm "${NEWEST_RPM}" "${thisrpm}")
    done

    echo "${NEWEST_RPM}"
}


#############################################################
#############################################################
IS_TESTING_REPO="FALSE"
CONFIG_FILE="/dev/null"

#############################################################
# setup args in the right order for making getopt evaluation
# nice and easy.  You'll need to read the manpages for more info
args=$(getopt -o hc: -- "$@")
eval set -- "$args"

for arg in $@; do
    case $1 in
        -- )
            # end of getopt args, shift off the -- and get out of the loop
            shift
            break 2
           ;;
         -c )
            # Source this config file
            CONFIG_FILE=$2
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
if [[ "${CONFIG_FILE}" == '/dev/null' ]]; then
    usage
fi

# We can do some rational guess work here...
#  Probably things should match their stored names...
#  But they might not and folks might want to change them.
REPO_KEY_TARGET_FILENAME=''
RELEASE_NOTES_OUTPUT_HTML_FILENAME=''

# pull in requested config
source ${CONFIG_FILE}

# run koji dist-repo
if [[ "${IS_TESTING_REPO}" == 'TRUE' ]]; then
    if [[ "x${YUM_GROUPS_FILENAME}" == 'x' ]]; then
        echo "koji dist-repo --with-src ${KOJI_TAG} ${REPO_KEY_ID}"
        koji dist-repo --with-src ${KOJI_TAG} ${REPO_KEY_ID}
    else
        echo "koji dist-repo --with-src --comps=${YUM_GROUPS_FILENAME} ${KOJI_TAG} ${REPO_KEY_ID}"
        koji dist-repo --with-src --comps=${YUM_GROUPS_FILENAME} ${KOJI_TAG} ${REPO_KEY_ID}
    fi
else
    if [[ "x${YUM_GROUPS_FILENAME}" == 'x' ]]; then
        echo "koji dist-repo --with-src --split-debuginfo --non-latest ${KOJI_TAG} ${REPO_KEY_ID}"
        koji dist-repo --with-src --split-debuginfo --non-latest ${KOJI_TAG} ${REPO_KEY_ID}
    else
        echo "koji dist-repo --with-src --split-debuginfo --non-latest --comps=${YUM_GROUPS_FILENAME} ${KOJI_TAG} ${REPO_KEY_ID}"
        koji dist-repo --with-src --split-debuginfo --non-latest --comps=${YUM_GROUPS_FILENAME} ${KOJI_TAG} ${REPO_KEY_ID}
    fi
fi

if [[ $? -ne 0 ]]; then
    echo "koji dist-repo failed!"
    exit 1
fi

echo ''

echo 'Time to sign our repodata:'
for repomd in $(find ${DIST_REPO_SYNC_SOURCE} -type f -name repomd.xml); do
    rm -f ${repomd}.asc
    gpg --detach-sign --armor ${repomd}
    chown apache:apache ${repomd}.asc
done

echo ''

# cleanup any old repodata just to be safe
find ${DIST_REPO_SYNC_TARGET} -type d -name repodata -exec rm -rf {} 2>/dev/null \;

# sync over the dist-repo
echo "rsync -avH --delete ${DIST_REPO_SYNC_SOURCE} ${DIST_REPO_SYNC_TARGET}"
rsync -avH --delete ${DIST_REPO_SYNC_SOURCE} ${DIST_REPO_SYNC_TARGET}
if [[ $? -ne 0 ]]; then
    echo "rsync failed, that is not good...."
    exit 1
fi

echo ''

if [[ "${IS_TESTING_REPO}" != 'TRUE' ]]; then
    # put GPG key file at the top of the tree
    if [[ "x${REPO_KEY_SOURCE_FILENAME}" != 'x' ]]; then
        if [[ "x${REPO_KEY_TARGET_FILENAME}" == 'x' ]]; then
            REPO_KEY_TARGET_FILENAME=$(basename ${REPO_KEY_SOURCE_FILENAME})
        fi
        echo "Making ${REPO_KEY_TARGET_FILENAME}"
        cp ${REPO_KEY_SOURCE_FILENAME} ${DIST_REPO_SYNC_TARGET}/${REPO_KEY_TARGET_FILENAME}
    fi

    # build release notes at the top of the tree
    if [[ "x${RELEASE_NOTES_SOURCE_ADOC_FILENAME}" != 'x' ]]; then
        if [[ "x${RELEASE_NOTES_OUTPUT_HTML_FILENAME}" == 'x' ]]; then
            RELEASE_NOTES_OUTPUT_HTML_FILENAME=$(basename ${RELEASE_NOTES_SOURCE_ADOC_FILENAME} | sed -e 's/\.adoc/.html/')
        fi
        echo "Making ${RELEASE_NOTES_OUTPUT_HTML_FILENAME}"
        asciidoc -a data-uri -a icons -o ${DIST_REPO_SYNC_TARGET}/${RELEASE_NOTES_OUTPUT_HTML_FILENAME} ${RELEASE_NOTES_SOURCE_ADOC_FILENAME}
    fi

    for seed in "${INITIAL_REPO_RPM}" "${INITIAL_AUTOMATION_RPM}"; do
        if [[ "x${seed}" != 'x' ]]; then
            # small sanity check here to be sure it really is noarch
            FILENAME=$(find ${DIST_REPO_SYNC_TARGET} -type f -name "${seed}" | grep noarch | head -1)
            SAMEDIR=$(dirname $FILENAME)
            SAMEDIR_REPOLOCAL=$(echo ${SAMEDIR} | sed -e "s|${DIST_REPO_SYNC_TARGET}||")
            PACKAGE_NAME=$(rpm -qp --qf "%{NAME}" ${FILENAME})
            NEWEST_TOP_RPM=$(basename $(newest_rpm_from_list $(ls ${SAMEDIR}/${PACKAGE_NAME}*.noarch.rpm | grep -v mirror | tr '\012' ' ')))
        
            echo "Making ${PACKAGE_NAME}.rpm"
            (
             cd ${DIST_REPO_SYNC_TARGET};
             ln -s ${SAMEDIR_REPOLOCAL}/${NEWEST_TOP_RPM} ${PACKAGE_NAME}.rpm
            )
        fi
    done

    echo ''
fi

echo "Running chown -Rh ${CHOWN_AS} ${DIST_REPO_SYNC_TARGET}"
chown -Rh ${CHOWN_AS} ${DIST_REPO_SYNC_TARGET}/*

echo "Hardlinking ${DIST_REPO_SYNC_TARGET}"
hardlink -c -v ${DIST_REPO_SYNC_TARGET}

echo ''

echo "Repo from ${KOJI_TAG} at ${DIST_REPO_SYNC_TARGET} ready for sync"

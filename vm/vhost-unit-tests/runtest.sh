#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of vhost tests
#   Description: Vhost tests
#   Author: Eugenio Perez <eperezma@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

unset ARCH
unset STANDALONE
RELEASE=$(uname -r | sed s/\.`arch`//)
HW_PLATFORM=$(uname -i)
LINUX_SRCDIR="/usr/src/kernels/$RELEASE.$HW_PLATFORM"
TEST_SRCDIR="$LINUX_SRCDIR/tools/virtio"
declare -r \
    HW_PLATFORM \
    LINUX_SRCDIR \
    PACKAGE="kernel-${RELEASE}" \
    RELEASE \
    TEST_SRCDIR

#
# A simple wrapper function to skip a test because beakerlib doesn't support
# such an important feature, right here we just leverage 'beaker'. Note we
# don't call function report_result() as it directly invoke command
# rstrnt-report-result actually
#
# Taken from vm/kvm-self-tests
#
function rlSkip
{
    rlLog "Skipping test because $*"
    rstrnt-report-result $TEST SKIP $OUTPUTFILE

    #
    # As we want result="Skip" status="Completed" for all scenarios, right here
    # we always exit 0, otherwise the test will skip/abort
    #
    exit 0
}

function check_platform_support
{
    declare -r hwpf=${1?"*** what hardware-platform?, e.g. x86_64"}
    [[ $hwpf == "x86_64" ]] && return 0
    [[ $hwpf == "aarch64" ]] && return 0
    [[ $hwpf == "ppc64" ]] && return 0
    [[ $hwpf == "ppc64le" ]] && return 0
    [[ $hwpf == "s390x" ]] && return 0
    return 1
}

function runtest
{
    rlPhaseStartTest 'virtio_test'

    rlRun "pushd '${TEST_SRCDIR}'"

    # Run tests
    rlRun -l './virtio_test'
    rlRun -l './vringh_test'
    rlRun 'popd'

    rlPhaseEnd
}

function setup
{
    declare tempdir
    declare -ar patches=(patches/0*.patch)

    rlPhaseStartSetup
    check

    declare -ar modules=(vhost)

    # Reload all modules
    rlRun "modprobe -r vhost"
    rlRun "modprobe vhost"

    tempdir=$(mktemp -d -p /var/tmp/)
    declare -r tempdir

    rlRun "pushd $tempdir"
    declare -r kernel_version=${RELEASE%%-*}
    declare -r kernel_release=${RELEASE##*-}

    rlRun 'dnf install -y patch elfutils-libelf-devel'
    rlRpmInstall "kernel-devel" "$kernel_version" "$kernel_release" \
                 "$HW_PLATFORM"

    rlFetchSrcForInstalled "${PACKAGE}"
    declare -r rpmfile="${tempdir}/${PACKAGE}.src.rpm"
    rlRun "rpm -ivh --define '_topdir $tempdir' $rpmfile" 0

    declare -r linux_tarball="${tempdir}/SOURCES/linux-${RELEASE}.tar.xz"
    rlAssertExists "${linux_tarball}"

    rlRun "cd '${LINUX_SRCDIR}'"
    rlRun "tar Jvxf '${linux_tarball}' --strip-components=1 'linux-${RELEASE}/tools/virtio'"
    rlRun "tar Jvxf '${linux_tarball}' --strip-components=1 'linux-${RELEASE}/tools/include/uapi/linux/vhost.h'"
    rlRun "tar Jvxf '${linux_tarball}' --strip-components=1 'linux-${RELEASE}/tools/include/linux/types.h'"
    rlRun "tar Jvxf '${linux_tarball}' --strip-components=1 'linux-${RELEASE}/drivers/vhost/'"
    rlRun "tar Jvxf '${linux_tarball}' --strip-components=1 'linux-${RELEASE}/drivers/virtio/virtio_ring.c'"
    rlRun 'popd'

    for m in "${patches[@]}"; do
        rlRun "patch -d '${LINUX_SRCDIR}' -p1 < '$m'" 0 \
              "Patching via '$m'"
    done

    rlRun "pushd '${LINUX_SRCDIR}/tools/virtio'"
    rlRun 'make'
    rlRun 'insmod vhost_test/vhost_test.ko'
    rlRun 'popd'

    rlPhaseEnd
}

function main
{
    rlJournalStart

    setup
    runtest

    rlJournalEnd
}

main

#!/bin/sh

# (c) Copyright 2018-2019 by Quinn Jones, quinn_jones@pobox.com
# All rights reserved.  The file named LICENSE specifies the terms
# and conditions for redistribution.
#
# Try executing with --help or --man for information

DEBUG=0
VERBOSE=0

TYPE=client

PATH=/bin:/usr/bin:/sbin:/usr/sbin

PORTDIR=/usr/portage
SYNC=1
SYNC_CMD='emerge --sync'
INDEX_CMD='eix-update'

FILENAME=portage.sqfs
SQFS=/opt/$FILENAME
REMOTE_SQFS=/net/fileserver/opt/$FILENAME

# server-only options
MKSQUASHFS_CMD=mksquashfs
MKSQUASHFS_OPTS=( -comp xz
                  -no-progress
                )
UNSQUASHFS_CMD=unsquashfs
UNSQUASHFS_OPTS=( -f -n )

SQUASHFS_MOUNT_OPTS=( -o loop
                      -t squashfs
                    )

TMPFS_MOUNT_OPTS=( -t tmpfs )

PROGNAME=$(basename $0)

function _debug
{
    if [ "$DEBUG" == 1 ]; then
        echo "$@"
    fi
}

function _log
{
    echo "$@"
}

function _error_exit
{
    echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

function _help
{
    cat <<EOL
portage.sh [options]

Defaults to being a $TYPE.

Try --man for more information.
EOL

    exit 254
}

function _man
{
    cat <<EOF
NAME
    portage.sh - Update the local portage tree using squashfs files

SYNOPSIS
    execute as a $TYPE:
      portage.sh

    force execution as a client, copying and mounting a squashed file:
      portage.sh -c

    execute as a server and sync against a public server:
      portage.sh -s

DESCRIPTION
    An efficient way to store and access your portage dir is by
    keeping it in a squashed filesystem.  This lowers the overhead
    associated with storing the directory, and radically improves
    access times by allowing the entire portage tree to be kept in
    cache, even on modest machines.

    This script automates two related tasks:

    1) sync a local server to a public portage server, creating an
       up-to-date copy of the squashed file system;
    2) sync a local client to the server by copying the squashed file
       system from the server (via NFS or similar network storage).

    For the sake of efficiency, the server copies the "old" portdir
    to a tmpfs to be used as a starting point to sync with a public
    server; the tmpfs is then used to create the updated, squashed
    portdir.

    Clients copy the squashed file from the server to a local file
    system.  This is most useful for clients like laptops that may
    be disconnected from the LAN.

    There may be minor advantages for SSD and flash storage in that
    overall writes may be reduced.

    Given the previous description, several dependencies stand out:

    * a kernel compiled with SQUASHFS, SQUASHFS_XZ, and TMPFS
    * 'sys-fs/squashfs-tools' installed on the local server
    * a shared network file system with which to share the file to
      clients.

    You should also add the following line to /etc/fstab, adjusting
    the path as necessary:

        $SQFS $PORTDIR squashfs loop 0 0

OPTIONS

    -c, --client
        Act as a client, taking a copy of the portage tree from a
        server.  This is the default, override with --server.

    --debug
        Enable debugging messages

    --index 'PATH [options]'
        Set an alternative portage indexing command, i.e.
        'app-portage/eix' or similar.  Include any arguments by
        using quotes around the command and arguments.
        
        Defaults to '$INDEX_CMD'.

    -h, --help
        Print a help message

    --local-path
        Set the local portage file location.  Defaults to '$SQFS'.

    --man
        Print a man page

    --portdir
        Set the parent portage directory.  Defaults to '$PORTDIR'.

    -s, --server
        Update a server's portage copy, which drops and re-shares NFS
        during the process and puts the squashed portage file into a
        shared location

    --no-sync
        (server mode) Do everything but an actual sync with public
        servers.  Useful for avoiding bans while testing.

    --remote-path PATH
        Set a pick-up location for new squashed portage files.  Defaults
        to '$REMOTE_SQFS'.

    -v, --verbose
        Enable verbose messages

EOF

    exit 254
}

function _verbose
{
    if [ "$VERBOSE" == 1 ]; then
        echo "$@"
    fi
}

function cleanup
{
    # make sure something is mounted at $PORTDIR, even if it's the
    # old file
    if !( mountpoint "$PORTDIR" > /dev/null ); then
        _verbose "mounting $PORTDIR"
        mount $PORTDIR
    fi

    if [ -n "$nfsopts" ]; then
        reexport ${nfsopts[@]}
        unset nfsopts
    fi

    if [ -d "$tmpdir" ]; then
        _verbose "cleaning up tempfile(s)"
        rm -Rf "$tmpdir"
        unset tmpdir
    fi

    if ( hash "$INDEX_CMD" ); then
        _debug "$INDEX_CMD"
        $INDEX_CMD
    fi
}

function deexport
{
    while [[ $# -gt 0 ]]; do
        host=$1; shift; shift

        _verbose "de-exporting $host:$PORTDIR"
        _debug "exportfs -u $host:$PORTDIR"
        exportfs -u $host:$PORTDIR
    done
}

function mount_portage
{
    sqfs=${1:-$SQFS}
    portdir=${2:-$PORTDIR}
    opts=${3:-${SQUASHFS_MOUNT_OPTS[@]}}

    unmount $portdir

    _verbose "mounting $sqfs as $portdir"
    _debug "mount $opts $sqfs $portdir"
    mount ${opts[@]} $sqfs $portdir
}

function reexport
{
    while [[ $# -gt 0 ]]; do
        host=$1; shift;
        opts=$1; shift

        _verbose "re-exporting $host:$PORTDIR"
        _debug "exportfs -o $opts \"$host:$PORTDIR\""
        exportfs -o $opts "$host:$PORTDIR"
    done
}

function unmount
{
    path=$1

    if mountpoint $path > /dev/null; then
        _verbose "unmounting $path"
        umount $path
    fi
}

while [[ $# -gt 0 ]]; do
    key="$1"

    _debug "1:$1 2:$2"

    shift

    case $key in
        -c|--client)
        TYPE=client
        ;;
        --debug)
        DEBUG=1
        ;;
        -h|--help)
        _help
        ;;
        --index)
        EIX_CMD=$1
        shift
        ;;
        --local-path)
        SQFS=$1
        shift
        ;;
        --man)
        _man
        ;;
        --mksquashfs)
        MKSQUASHFS_CMD=$1
        shift
        ;;
        --portdir)
        PORTDIR=$1
        shift
        ;;
        --remote-path)
        REMOTE_SQFS=$1
        shift
        ;;
        -s|--server)
        TYPE=server
        ;;
        --sync)
        SYNC=1
        ;;
        --no-sync)
        SYNC=0
        ;;
        --unsquashfs)
        UNSQUASHFS_CMD=$1
        shift
        ;;
        -v|--verbose)
        VERBOSE=1
        ;;
    esac
done

if [[ $TYPE == "server" ]]; then
    _debug "server mode"

    if !( type $MKSQUASHFS_CMD > /dev/null ); then
        _error_exit "$MKSQUASHFS_CMD cannot be found"
    elif !( type $UNSQUASHFS_CMD > /dev/null ); then
        _error_exit "$UNSQUASHFS_CMD cannot be found"
    fi

    trap cleanup SIGHUP SIGINT SIGTERM

    #
    # un-share $PORTDIR and umount it so we can update it
    #

    _debug "exportfs -s | grep \"^$PORTDIR\""
    nfsmount=`exportfs -s | grep "^$PORTDIR"`
    _debug "nfsmount:$nfsmount"

    if [[ -n $nfsmount ]]; then
        nfsopts=$( echo ${nfsmount#$PORTDIR} | sed -r 's_([^(]+)\(([^)]+)\)\s*_\1 \2\n_g' )
        _debug "nfsopts:${nfsopts[@]}"

        deexport ${nfsopts[@]}
    fi

    unmount $PORTDIR

    #
    # set up portdir at /usr/portage so rsync can work efficiently
    #

    _verbose "mounting $PORTDIR as a tmpfs"
    _debug "mount ${TMPFS_MOUNT_OPTS[@]} tmpfs $PORTDIR"
    mount ${TMPFS_MOUNT_OPTS[@]} tmpfs $PORTDIR

    _debug "$UNSQUASHFS_CMD ${UNSQUASHFS_OPTS[@]} -d $PORTDIR -f $SQFS"
    $UNSQUASHFS_CMD ${UNSQUASHFS_OPTS[@]} -d $PORTDIR -f $SQFS

    if [ "$SYNC" == "1" ]; then
        _verbose "syncing $PORTDIR"
        _debug "$SYNC_CMD"
        $SYNC_CMD
    fi

    #
    # if making a new squashfs file is successful, we'll replace old
    # with new
    #

    _verbose "squashing the new portage copy"

    tmpdir="$(mktemp --directory)"
    tmpfile="$tmpdir/$FILENAME"

    _debug "$MKSQUASHFS_CMD $PORTDIR $tmpfile ${MKSQUASHFS_OPTS[@]}"
    if $MKSQUASHFS_CMD $PORTDIR $tmpfile ${MKSQUASHFS_OPTS[@]} > /dev/null; then
        _debug "mv $tmpfile $SQFS"
        mv $tmpfile $SQFS
    else
        _error_exit "bad sync"
    fi

    #
    # regardless of outcome mount $SQFS back onto $PORTDIR, restore
    # exports, and clean up any temp files
    #

    mount_portage

    cleanup
else
    _debug "client mode"

    _verbose "copying squashed copy of $PORTDIR from '$REMOTE_SQFS'"

    if [ ! -r $REMOTE_SQFS ]; then
        _error_exit "'$REMOTE_SQFS' cannot be accessed"
    fi

    # avoid leaving a file behind to be cleaned up
    _debug "creating anonymous temp file"
    tmpfd="/dev/fd/3"
    tmpfile=$(mktemp)
    exec 3>"$tmpfile"
    rm "$tmpfile"

    _debug "cat $REMOTE_SQFS >$tmpfd"
    cat $REMOTE_SQFS >$tmpfd

    if [ ! -s $tmpfd ]; then
        _error_exit "No bytes copied from $REMOTE_SQFS"
    fi

    # MD5 has the following advantages:
    # - it's fast (faster than cksum)
    # - it's accurate
    # - it's guaranteed to be in any Gentoo installation
    old_md5=$(md5sum "$SQFS" | awk '{print $1}')
    new_md5=$(md5sum <$tmpfd | awk '{print $1}')

    _debug "old_md5:$old_md5"
    _debug "new_md5:$new_md5"

    if [[ "$old_md5" == "$new_md5" ]]; then
        _log "old and new files match, no changes made"
    else
        _verbose "updating portage to current copy"

        if mountpoint $PORTDIR > /dev/null; then
            _verbose "unmounting $PORTDIR"
            unmount $PORTDIR
        fi

        _debug "cat <$tmpfd >$SQFS"
        cat <$tmpfd >$SQFS

        mount_portage

        _log "Updated portage"
    fi
fi

exit


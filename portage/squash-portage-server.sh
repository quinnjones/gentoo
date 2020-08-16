#!/bin/env bash

# Copyright (C) 2020 by Quinn Jones, quinn_jones@pobox.com
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA.
#
# Try executing with --help or --man for information

# pull in portage settings
source /etc/portage/make.conf

################################
# begin user-serviceable parts #
################################

PATH=/bin:/usr/bin:/sbin:/usr/sbin

# if true, enables debug messaging (--debug)
DEBUG=

# if true, mounts the squashed filesystem to $PORTAGE (--mount)
MOUNT=

# if true, enables verbose output to show work being done (--verbose)
VERBOSE=

# use tmpfs by default for the temporary sync location (--tmp-location)
tmpfs="tmpfs"

# where the squashed file winds up (--destination)
path="$PORTDIR.sqfs"

# which emaint program to run, and repo to sync (--emaint)
emaint=
# repo to squash (--repo)
repo=gentoo

# update eix if it's installed (--eix-update, --no-eix)
eixupdate=$(which eix-update)

# mksquashfs and unsquashfs executable locations and options
# (--mksquashfs, --mksquashfs-opts, --unsquashfs, --unsquashfs-opts)
mksq=$(which mksquashfs)
mksq_opts=( -comp gzip
            -no-progress
            -noappend
          )

unsq=$(which unsquashfs)
unsq_opts=( -f -n )

# rsync, which is used as a fallback if a squashed portage isn't
# available (--rsync, --rsync-opts)
rsync=$(which rsync)
rsync_opts=( -a
             --exclude=/distfiles/
             --exclude=/packages/
           )

##############################
# end user-serviceable parts #
##############################

# cause all errors to exit
set -e

progname=$(basename $0)

function _debug
{
    if [ -n "$DEBUG" ]; then
        echo "$@"
    fi
}

function _log
{
    echo "$@"
}

function _verbose
{
    if [ -n "$VERBOSE" ]; then
        echo "$@"
    fi
}

function _error_exit
{
    echo "${progname}: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

function _help
{
    cat <<-EOF
	$progname [options]

	Try --man for detailed help

EOF
}

function _man
{
    cat <<-EOF
	NAME
	
	    $progname - Update and squash portage
	
	SYNOPSIS
	
	    $progname [options]
	
	DESCRIPTION
	
	    Squash your portage tree, optionally after syncing it.
	
	    If a previously-squashed filesystem already exists in the
	    target location it shall be used to 'prime' the portage
	    tree; if the file does not exist then a copy of PORTDIR
	    shall be made using rsync. By default, the portage tree is
	    then synced.
	
	    After squashing, the program may optionally mount the
	    squashed filesystem locally as PORTDIR.
	
	Options
	
	    --debug, --no-debug
	        Enable/disable debugging output
	
	    --destination, -d
	        Specify an alternate location to save the squashed repo.
	        You may want to specify a path inside an existing shared
	        directory, for example.
	
	        Defaults to "$path".
	
	    --emaint
	        Specify an alternative emaint executable. Implies --sync.
	
	    --eix-update, --no-eix
	        Specify an alternative eix-update binary, or disable eix
	        indexing even if it's installed.
	
	    --help, -h
	        Display a basic help message
	
	    --man
	        Display comprehensive help
	
	    --mksquashfs
	        Specify an alternate "mksquashfs" executable
	
	    --mksquashfs-opt
	        Add options to be passed to mksquashfs. May be given
	        multiple times.
	
	    --mount, --no-mount
	        After squashing the repo, it may optionally be mounted at
	        PORTDIR. Existing sub-mounts and NFS exports shall be
	        saved and remounted/re-exported.
	
	    --path
	        Specify an alternate PATH, which affects where the default
	        executables will be found.
	
	        Defaults to "$PATH".
	
	    --portdir
	        Specify an alternate location for "PORTDIR"; defaults to
	        whatever you've set in "make.conf", currently set to
	        "$PORTDIR".
	
	    --repo
	        Specify an alternate repo to squash.
	
	        Defaults to "$repo".
	
	    --rsync
	        Specify an alternate "rsync" executable
	
	    --rsync-opts
	        Add options to be passed to rsync. May be given multiple
	        times.
	
	    --sync, --no-sync
	        Execute "emaint sync" on the repo before squashing it
	
	    --unsquashfs
	        Specify an alternate "unsquashfs" executable
	
	    --unsquashfs-opt
	        Add options to be passed to unsquashfs. May be given
	        multiple times.
	
	    --tmp-location
	        Assign an alternate location for mounting, copying,
	        syncing, and squashing portage. Default is to create a
	        tmpfs mount.
	
	    --tmp-location-opt
	        Set options for the mount command when mounting the tmp
	        location
	
	    --verbose, -v, --no-verbose
	        Enable/disable verbose output showing current activity
	
	Mounted Filesystems
	    If the option to mount the squashed filesystem at PORTDIR
	    after squashing is used, some considerations are taken:
	
	    Sub-mounts
	        File systems mounted under PORTDIR shall be unmounted and
	        re-mounted afterwards. These mounts may fail if the target
	        directory is no longer available.
	
	    Exported Filesystems
	        If PORTDIR or a subdirectory is exported via NFS, the
	        export shall be un-exported and re-exported.
	
	Requirements
	
	    * sys-fs/squashfs-tools
	    * net-misc/rsync
	    * ~600 megs of free RAM (if using the default tmpfs). The
	      RAM is consumed temporarily, and released after squashing.
	    * kernel support for squashfs, if mounting the squashed file-
	      system locally afterwards.
	
	    Optional Packages
	
	        * app-portage/eix for fast portage indexing
	        * net-fs/nfs-utils to export filesystems over NFS
	
	Performance
	
	    As of this writing, an uncompressed portage tree consumes
	    nearly 300 MB of disk space; a gzip-squashed filesystem
	    consumes less than 60 MB.
	
	    It is frequently faster to copy the squashed filesystem
	    between nodes than rsyncing portage, even if the rsync
	    occurs between nodes on the LAN.
	
	    Reading portage, e.g. calculating dependencies, may be
	    faster when backed by a squashed filesystem. The entire
	    file can be effectively cached in memory by the kernel,
	    reducing disk accesses.
	
	    As always, everyone's situation is a little different,
	    read all rules and conditions, YMMV.
	
	EXAMPLES
	
	    I like to keep a copy of a squashed portage on my file server
	    under /storage, which is accessible to other machines on my
	    LAN. I run this script weekly via cron.
	
	        $progname --sync --mount \\
	            --destination /storage/portage.sqfs
	
	    You may also squash overlay repos. If you use the popular
	    'andy' overlay, your command might look like:
	
	        $progname --sync --mount \\
	            --portdir /var/db/repos/andy \\
	            --repo andy --destination /storage/andy.sqfs \\
	
	    Clients may use a simpler script to copy the squashed portage
	    and mount it to their PORTDIR location. See my github for
	    a script that does this.
	
	TERMS & CONDITIONS
	
	    The above shall not be construed to imply fitness for any
	    particular use. There are no guarantees. Always test on
	    something unimportant before using on a critical task.
	
	LICENSE
	
	    Licensed under the GPLv2.
	
	AUTHOR
		
	    Quinn Jones, quinn_jones@pobox.com
	    Github: https://github.com/quinnjones
		
EOF
}

function cleanup
{
    _verbose cleaning up

    # delete temporary files and directories

    local dir

    for dir in $portdir; do
        if [[ -d "$dir" ]]; then
            if ( mountpoint "$portdir" > /dev/null ); then
                unmount $portdir
            fi
        fi
    done

    for dir in "$portdir" "$tmpdst"; do
        if [[ -d "$dir" ]]; then
            _debug rm -Rf "$dir"
            rm -Rf "$dir"
        fi
    done

    unset portdir
    unset tmpdst

    # remount and re-export things we might have unmounted
    remount
    reexportnfs
}

function unexportnfs
{
    local portdir=$1; shift

    # definitely want this to be global so we can access it when we
    # re-export the filesystem(s) later
    nfsmount=($( exportfs -s | grep "^$portdir[/[:space:]]" | sort ))

    # process from deepest path to shallowest
    if [[ -n $nfsmount ]]; then
        for (( i=${#nfsmount[@]}; i>=0; i=$i-2 )); do
            local dir=${nfsmount[$i-1]}
            local attr=( $(echo "${nfsmount[$i]}" | sed -r 's_([^(]+)\(([^)]+)\)\s*_\1 \2\n_g' ) )
            local hosts=$attr[0]
            local opts=$attr[1]

            exportfs -u "$hosts:$dir"
        done
    fi
}

function reexportnfs
{
    # process from shallowest path to deepest
    if [[ -n $nfsmount ]]; then
        for (( i=0; i<=${#nfsmount[@]}; i=$i+2 )); do
            local dir=${nfsmount[$i]}
            local attr=( $(echo "${nfsmount[$i+1]}" | sed -r 's_([^(]+)\(([^)]+)\)\s*_\1 \2\n_g' ) )
            local hosts=$attr[0]
            local opts=$attr[1]

            exportfs -o $opts "$host:$dir"
        done

        unset nfsmount
    fi
}

function unmount
{
    local path
    for path in $@; do
        _debug checking if $path is mounted
        if mountpoint "$path" > /dev/null; then
            submount+=($( findmnt -Rr "$path" | grep "^$path/" | sort ))
            _verbose "unmounting $path and submounts"
            umount -R "$path"
        fi
    done
}

function remount
{
    local path=$1; shift
    # make sure something is mounted at $PORTDIR, even if it's the
    # old file
    if !( mountpoint "$path" > /dev/null ); then
        _verbose "mounting $path"
        mount $path
    fi

    if [[ -n $submount ]]; then
        for (( i=0; i<${#submount[@]}; i=$i+4 )); do
            local dir=${submount[$i+0]}
            local dev=${submount[$i+1]}
            local fst=${submount[$i+2]}
            local opt=${submount[$i+3]}

            _verbose mounting $dir
            _debug mount -o $opt -t $fst $dev $dir
            mount -o $opt -t $fst $dev $dir
        done

        unset submount
    fi
}

trap cleanup SIGHUP SIGINT SIGTERM EXIT

while [[ $# -gt 0 ]]; do
    key="$1"

    _debug "1:$1 2:$2"

    shift

    case $key in
        --debug             ) DEBUG=1 ;;
        --no-debug          ) unset DEBUG ;;
        --destination|-d    ) path=$1; shift ;;
        --emaint            ) emaint=$1; shift ;;
        --eix-update        ) eixupdate=$1; shift ;;
        --no-eix            ) unset eixupdate ;;
        --help|-h           ) _help; exit ;;
        --man               ) _man; exit ;;
        --mksquashfs        ) mksq=$1; shift ;;
        --mksquashfs-opt    ) mksq_opts+=$1; shift ;;
        --mount             ) MOUNT=1 ;;
        --no-mount          ) unset MOUNT ;;
        --path              ) PATH=$1; shift ;;
        --portdir           ) PORTDIR=$1; shift ;;
        --repo              ) repo=$1; shift ;;
        --rsync             ) rsync=$1; shift ;;
        --rsync-opts        ) rsync_opts+=$1; shift ;;
        --sync              ) emaint=${emaint:-$(which emaint)} ;;
        --no-sync           ) unset emaint ;;
        --unsquashfs        ) unsq=$1; shift ;;
        --unsquashfs-opt    ) unsq_opts+=$1; shift ;;
        --tmp-location      ) tmpfs=$1; shift ;;
        --tmp-location-opt  ) tmpfs_opts+=$1; shift ;;
        --verbose|-v        ) VERBOSE=1 ;;
        --no-verbose        ) unset VERBOSE ;;
    esac
done

_debug \$path:$path

basedir=$(dirname $path)
file=$(basename $path)

_debug \$basedir:$basedir \$file:$file

#
# basic error checking
#

if [[ -z "$PORTDIR" ]]; then
    _error_exit "\$PORTDIR not set"
elif [[ -z "$mksq" ]]; then
    _error_exit "Cannot locate mksquashfs"
elif [[ -z "$unsq" ]]; then
    _error_exit "Cannot locate unsquashfs"
elif [[ -z "$basedir" || "$basedir" == "." ]]; then
    _error_exit "Destination must be a fully-qualified path"
elif [[ -z "$file" ]]; then
    _error_exit "Destination may not be empty"
fi

portdir=$PORTDIR

_debug \$portdir:$portdir \$PORTDIR:$PORTDIR

# copy the existing squashed portdir or current portdir to a temporary
# location. That location will (optionally) be sync'ed and used to
# create a new squashed portage
if [[ -n $tmpfs ]]; then
    portdir=$(mktemp -d);

    _verbose mounting temporary location

    if [[ -n "$tmpfs_opts" ]]; then
        tmpfs_opts=( -o ${tmpfs_opts[@]} )
    fi

    fstype="auto"

    if [[ "$tmpfs" == "tmpfs" ]]; then
        fstype="tmpfs"
    fi

    _debug mount -t $fstype $tmpfs_opts "$tmpfs" "$portdir"
    mount -t $fstype $tmpfs_opts "$tmpfs" "$portdir"

    _verbose copying portage to temporary location

    if [[ -f "$path" ]]; then
        _debug "$unsq" -d "$portdir" $unsq_opts "$path"
        "$unsq" -d "$portdir" $unsq_opts "$path"
    else
        portdircontents="$(ls -A $PORTDIR)"

        if [[ -z $portdircontents ]]; then
            portdir_orig=$PORTDIR

            export PORTDIR=$portdir
            _debug emerge-webrsync
            emerge-webrsync

            PORTDIR=$portdir_orig
        else
            _debug $rsync $rsync_opts $PORTDIR/ $portdir
            "$rsync" $rsync_opts "$PORTDIR/" "$portdir"
        fi
    fi
fi

# sync portage
if [[ -n "$emaint" ]]; then
    _verbose syncing portage

    portdir_orig=$PORTDIR

    export PORTDIR=$portdir
    _debug $emaint sync $repo
    "$emaint" sync --repo $repo

    PORTDIR=$portdir_orig
fi

# squash portage
_verbose squashing temporary location

tmpdst=$(mktemp)
_debug "$mksq" "$portdir" "$tmpdst" ${mksq_opts[@]}
"$mksq" "$portdir" "$tmpdst" ${mksq_opts[@]}

_debug mkdir -p $basedir
mkdir -p "$basedir"

_debug mv "$tmpdst" "$path"
mv "$tmpdst" "$path"
_debug chmod 644 "$path"
chmod 644 "$path"

# mount the squashed filesystem at $PORTDIR, if requested
if [[ -n "$MOUNT" ]]; then
    unexportnfs "$PORTDIR"
    unmount "$PORTDIR"

    _verbose mounting $PORTDIR
    _debug mount -o loop -t squashfs "$path" "$PORTDIR"
    mount -o loop -t squashfs "$path" "$PORTDIR"

    if [[ -n "$eixupdate" ]]; then
        _debug $eixupdate
        $eixupdate
    fi
fi

exit


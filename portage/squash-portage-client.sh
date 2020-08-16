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

# if true, enables verbose output to show work being done (--verbose)
VERBOSE=

dst=$PORTDIR.sqfs

eixupdate=$(which eix-update)

cksum=$(which md5sum)

rsync=$(which rsync)
rsync_opts=( -q )

src=$SQUASHED_SRC

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

function _verbose
{
    if [ -n "$VERBOSE" ]; then
        echo "$@"
    fi
}

function _log
{
    echo "$@"
}

function _error
{
    echo "$@"
}

function _error_exit
{
    echo "${progname}: ${1:-"Unknown Error"}" 1>&2
    exit 1
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

    if !( mountpoint "$path" > /dev/null ); then
        _verbose "mounting $path"
        _debug mount $path
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

function cleanup
{
    _verbose cleaning up

    local file

    for file in "$tmpfile"; do
        if [[ -f "$file" ]]; then
            _debug rm $file
            rm $file
        fi
    done
}

function _help
{
    cat <<-EOF
	$progname [options] -s /src/file -d /dst/file

    Try --man for detailed help
	
	EOF
}

function _man
{
    cat <<-EOF
	NAME
	
	    $progname - Copy a squashed portage and mount it at PORTDIR
	
	SYNOPSIS
	
	    $progname -s /net/files/storage/portage.sqfs \\
	        -d /var/db/repos/gentoo.sqfs
	
	DESCRIPTION
	
	    If you're squashing portage you can distribute it to other
	    Gentoo machines on your network to take advantage of faster
	    syncing and searching.
	
	    This script copies the file from a source location, compares
	    it to the current copy, and if the file has changed mounts
	    it at PORTDIR.
	
	Options
	
	    --debug, --no-debug
	        Enable/disable debugging output
	
	    --destination, --dest, -d
	        Specify a location to store the squashed portage.
	
	    --eix-update, --no-eix
	        Specify an alternative eix-update binary, or disable eix
	        indexing even if it's installed.
	
	    --help, -h
	        Display a basic help message
	
	    --man
	        Display comprehensive help
	
	    --portdir
	        Specify an alternative PORTDIR location. Default is to
	        use the PORTDIR defined in portage.conf.
	
	    --rsync
	        Specify an alternate "rsync" executable
	
	    --rsync-opts
	        Add options to be passed to rsync. May be given multiple
	        times.
	
	    --source, --src, -s
	        Source location of the squashed portage. May use rsync
	        host:src conventions.
	
	    --verbose, --no-verbose
	        Enable/disable verbose output showing current activity
	
	DEFAULTS
	
	A default source file may be set by adding a line like this to
	your environment or /etc/portage/make.conf:
	
	    SQUASHED_SRC=/path/to/squashed/file
	
	Setting this variable allows you skip the --source argument.
	
	The default destination file is $PORTDIR.sqfs.  Override it with
	--destination.
	
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

while [[ $# -gt 0 ]]; do
    key="$1"

    _debug "1:$1 2:$2"

    shift

    case $key in
        --debug                 ) DEBUG=1 ;;
        --no-debug              ) unset DEBUG ;;
        --destination|--dest|-d ) dst=$1; shift ;;
        --eix-update            ) eixupdate=$1; shift ;;
        --help                  ) _help; exit ;;
        --man                   ) _man; exit ;;
        --portdir               ) PORTDIR=$1; shift ;;
        --rsync                 ) rsync=$1; shift ;;
        --rsync-opts            ) rsync_opts+=$1; shift ;;
        --source|--src|-s       ) src=$1; shift ;;
        --verbose               ) VERBOSE=1 ;;
        --no-verbose            ) unset VERBOSE ;;
    esac
done

trap cleanup SIGHUP SIGINT SIGTERM EXIT

if [[ -z "$PORTDIR" ]]; then
    _error_exit "\$PORTDIR not set"
elif [[ -z "$dst" ]]; then
    _error_exit "Destination may not be empty"
elif [[ -z "$src" ]]; then
    _error_exit "Source file may not be empty"
fi


_verbose copying file from $src

basedir=$(dirname $PORTDIR)

_debug mkdir -p $basedir
mkdir -p $basedir

tmpfile=$(mktemp -p $basedir)

$rsync ${rsync_opts[@]} $src $tmpfile


_verbose "checking whether portage was updated"

oldcksum=$($cksum $dst     | awk '{print $1}')
newcksum=$($cksum $tmpfile | awk '{print $1}')

_debug "oldcksum:$oldcksum newcksum:$newcksum"

if [[ "$oldcksum" == "$newcksum" ]]; then
    _verbose "No updates found, no changes made"
else
    _verbose "portage has updates, applying them"

    unmount $PORTDIR

    _verbose "Replacing portage with updated copy"
    _debug mv "$tmpfile" "$dst"
    mv "$tmpfile" "$dst"

    _debug mount -o loop -t squashfs "$dst" "$PORTDIR"
    mount -o loop -t squashfs "$dst" "$PORTDIR"

    if [[ -n "$eixupdate" ]]; then
        _debug $eixupdate
        $eixupdate
    fi
fi

exit


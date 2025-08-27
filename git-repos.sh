#!/bin/sh
# Usage: update-all.sh
# Fetch all subrepos, as listed in '.gitignore'.
#
# Options:
#   -d,--dirty    List directories with uncommited changes
#   -h,--help     Display this help and exit
#   -l,--list     List subrepositories to fetch/update
#   -t,--test     Don't run Git stuff, just test
#   -v,--verbose  Show output debug output
#   -V,--version  Display version information and exit
#
# This is convenience script for fetching all the subrepositories of the
# zrajm.org website. These are not Git submodules, as the exact versioning is
# not that important (and there's a fiddly bit of overhead in updating each Git
# submodule).
#
# Instead most of the subrepositories are are their own articles for the
# zrajm.org website. One prominent exception to this is the 'www/' directory,
# which both contains the article 'HTML-scented Markdown' and the actual
# implementation of said Markdown, used by (most) of the other articles.
#
# As each subrepository dir is ignored for the parent 'zrajm.org' website, the
# list of subrepositories is stored in '.gitignore'.
set -eu

AUTHOR='zrajm <zrajm@zrajm.org>'
VERSION='0.1.0'                                # https://semver.org/
VERSION_DATE='27 August 2025'
CREATED_DATE='26 August 2025'            # never change this!

###############################################################################
say() { printf '%s\n' "$@"; }                       # safer than 'echo'
cat() { while IFS='' read -r X; do say "$X"; done } # built-ins only
die() {                                             # msg STDERR, then exit
    local X="$1"; shift; set -- "${0##*/}: $X" "$@"
    [ $# -eq 1 ] && \
        set -- "$@" "(See '${0##*/} --help' for more information.)"
    say "$@" >&2
    exit 5
}

###############################################################################
## Functions

# Display help information and exit.
# Output all leading comment lines (skip #!, stop at 1st non-# line).
help() {
    while read -r X; do
        case "$X" in
            '#!'*) continue ;;
            '#'*) ;;
            *) exit ;;
        esac
        # Strip one '#' and one space, then output.
        X="${X#\#}"; say "${X# }"
    done <"$0"
    exit 0
}

# Display version information and exit.
version() {
    local BEG="${CREATED_DATE##* }"
    local END="${VERSION_DATE##* }"
    local YEARS="$BEG"
    if [ "$BEG" != "$END" ]; then YEARS="$YEARS-$END"; fi
    say "${0##*/} $VERSION ($VERSION_DATE)" \
        "Copyright (C) $YEARS $AUTHOR" \
        "License GPLv2: GNU GPL version 2 <https://gnu.org/licenses/gpl-2.0.html>." \
        "This is free software: you are free to change and redistribute it."
    exit 0
}

###############################################################################

# Output the number of arguments given.
count() { say "$#"; }

# Loop through PIDs given as args, and output those that belong to processes
# that are still running.
get_running() {
    local PIDS=''
    for PID in "$@"; do
        [ -e "/proc/$PID" ] && PIDS="$PIDS$PID "
    done
    say "${PIDS% }"  # strip (one) trailing space
}

git_clone() {
    local URL="$1"
    say "Cloning: $DIR"
    say "  >>git clone '$URL'"
    git clone "$URL"
}

git_pull() {
    local DIR="$1"
    say "Pulling: $DIR"
    # Should spew out error if the directory isn't clean.
    cd "$DIR"
    say "  >>cd '$DIR'; git pull"
    git pull --recurse-submodules --ff-only
}

# Wait for a random while (up to 10 seconds).
dummywait() {
    #say "$1"
    sleep "$(perl -e 'print int(rand()*10)')"
}

# Kill any remaining child processes.
cleanup() {
    trap '' INT TERM EXIT
    if [ -n "$CHILD_PIDS" ]; then
        kill $CHILD_PIDS 2>/dev/null ||:
        wait
    fi
    [ -d "$TEMPDIR" ] && rm -r "$TEMPDIR"
}
interrupt() {
    printf '%s\e[K\n' '*** INTERRUPTED' >&2
    cleanup
}

###############################################################################
## Main

CHILD_PIDS=''
TEMPDIR="$(mktemp -qtd "${0##*/}-$$.XXXXXX")"  # create tempdir
trap cleanup EXIT
trap interrupt INT TERM

# Process command line arguments.
OPT_LIST=''; OPT_DIRTY=''; OPT_TEST=''; OPT_VERBOSE=''
for ARG in "$@"; do
    case "$ARG" in
        -h|--help) help ;;
        -l|--list) OPT_LIST=1 ;;
        -t|--test) OPT_TEST=1 ;;
        -s|--dirty) OPT_DIRTY=1 ;;
        -v|--verbose) OPT_VERBOSE=1 ;;
        -V|--version) version ;;
        -*) die "Unknown option '$ARG'" ;;
        *)  die "Unknown argument '$ARG'" ;;
    esac
done

# Read list of repositories (from '.gitignore').
FILE=.gitignore
STATE=start  # start | reading | end
DIRS=''
NL="$(printf '\nx')"; NL="${NL%x}"  #newline
while IFS='' read -r LINE; do
    case "$STATE" in
        start)
            case "$LINE" in *START-SUBREPOS*) STATE=reading;; esac ;;
        reading)
            case "$LINE" in *END-SUBREPOS*) STATE=end; break;; esac
            DIR="${LINE%/}"; DIR="${DIR#/}"; # strip leading & trailing '/'
            if [ -n "$DIR" ]; then
                DIRS="$DIRS${NL}$DIR"
            fi ;;
        end) break ;;
    esac
done <"$FILE"
case "$STATE" in
    start) die "Missing 'START-SUBREPOS' line in file '$FILE'" ;;
    reading) die "Missing 'END-SUBREPOS' line in file '$FILE'" ;;
esac

REMOTE_NAME="$(git remote show)"               # e.g. 'origin'
REMOTE_URL="$(git remote get-url "$REMOTE_NAME")" # repo url
REMOTE_BASE="${REMOTE_URL%%/*}"
[ -n "$OPT_VERBOSE" ] && say "Tempdir: $TEMPDIR"

# List repositories.
if [ -n "$OPT_LIST" ]; then
    while IFS='' read -r DIR; do
        [ -z "$DIR" ] && continue   # skip blank lines
        if (cd "$DIR"; git diff-index --quiet HEAD); then
            STATUS=-
        else
            STATUS=dirty
        fi
        printf '%s\t%s\n' "$STATUS" "$DIR"
    done <<-END_DIRS
	$DIRS
	END_DIRS
    exit 0
fi

# List dirs with uncommitted changes.
if [ -n "$OPT_DIRTY" ]; then
    while IFS='' read -r DIR; do
        [ -z "$DIR" ] && continue   # skip blank lines
        (
            cd "$DIR"
            if ! git diff-index --quiet HEAD; then
               printf '==> %s <==\n' "$DIR"
               git status --porcelain
            fi
        )
    done <<-END_DIRS
	$DIRS
	END_DIRS
    exit 0
fi

# Execute commands (in background).
while IFS='' read -r DIR; do
    [ -z "$DIR" ] && continue   # skip blank lines

    #say "$REMOTE_BASE/$DIR"
    if [ -f "$DIR" ]; then
        say "${0##*/}: File '$DIR' already exists, cannot fetch repo" >&2
        continue
    fi

    # Run a git command (or 'dummywait' in --test mode).
    if [ -n "$OPT_TEST" ]; then         # test mode, random wait
        dummywait "$DIR"
    elif [ -d "$DIR" ]; then            # already exists: 'git pull'
        git_pull "$DIR"
    elif [ ! -e "$DIR" ]; then          # not existing: 'git clone'
        git_clone "$REMOTE_BASE/$DIR"
    fi >"$TEMPDIR/$DIR.log" 2>&1 &
    CHILD_PIDS="$CHILD_PIDS $!"

done <<-END_DIRS
     	$DIRS
	END_DIRS

# Wait for child processes to finish.
while :; do
    CHILD_PIDS="$(get_running $CHILD_PIDS)"
    [ -z "$CHILD_PIDS" ] && break
    printf 'Running child processes: %s\e[K\r' "$(count $CHILD_PIDS)"
    sleep .5
done
#printf '%s\e[K\n' 'DONE'

#[eof]

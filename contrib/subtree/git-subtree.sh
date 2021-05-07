#!/usr/bin/env bash
#
# git-subtree.sh: split/join git repositories in subdirectories of this one
#
# Copyright (C) 2009 Avery Pennarun <apenwarr@gmail.com>
#

# Disable SC2004 ("note: $/${} is unnecessary on arithmetic
# variables"); while it's not nescessary, git.git code style until
# 2.27.0 was to include it.  It's not worth the patch-noise to remove
# them all now.
#
# Disable SC3043 ("In POSIX sh, 'local' is undefined"); it's not in
# POSIX, but it's very valuable and is supported in all shells that we
# care about.
#
# shellcheck disable=SC2004,SC3043

if test -z "$GIT_EXEC_PATH" || test "${PATH#"${GIT_EXEC_PATH}:"}" = "$PATH" || ! test -f "$GIT_EXEC_PATH/git-sh-setup"
then
	echo >&2 'It looks like either your git installation or your'
	echo >&2 'git-subtree installation is broken.'
	echo >&2
	echo >&2 "Tips:"
	echo >&2 " - If \`git --exec-path\` does not print the correct path to"
	echo >&2 "   your git install directory, then set the GIT_EXEC_PATH"
	echo >&2 "   environment variable to the correct directory."
	echo >&2 " - Make sure that your \`${0##*/}\` file is either in your"
	echo >&2 "   PATH or in your git exec path (\`$(git --exec-path)\`)."
	echo >&2 " - You should run git-subtree as \`git ${0##*/git-}\`,"
	echo >&2 "   not as \`${0##*/}\`." >&2
	exit 126
fi

# Globals:
#  - arguments:
#    + arg_FLAG (readonly except for arg_addmerge_message)
#    + arg_command (readonly)
#    + dir (readonly)
#  - misc:
#    + scratchdir (readonly)
#    + indent (mutable, kinda)
#    + split_started (mutable)

OPTS_SPEC="\
git subtree add   --prefix=<prefix> <commit>
git subtree add   --prefix=<prefix> <repository> <ref>
git subtree merge --prefix=<prefix> <commit>
git subtree split --prefix=<prefix> [<commit>]
git subtree pull  --prefix=<prefix> <repository> <ref>
git subtree push  --prefix=<prefix> <repository> <refspec>
--
h,help        show the help
q             quiet
d             show debug messages
P,prefix=     the name of the subdir to split out
 options for 'split' (also: 'push')
annotate=     add a prefix to commit message of new commits
b,branch=     create a new branch from the split subtree
ignore-joins  ignore prior --rejoin commits
onto=         try connecting new tree to an existing one
notree=       inform git-subtree that the commit is a parent-repo commit not containing the subtree, rather than a subtree-repo commit
rejoin        merge the new branch back into HEAD
remember=before:after  inform git-subtree that the commit 'before' had previously been split, creating 'after'
 options for 'add' and 'merge' (also: 'pull', 'split --rejoin', and 'push --rejoin')
squash        merge subtree changes as a single commit
m,message=    use the given message as the commit message for the merge commit
"

indent=0

# Usage: debug [MSG...]
debug () {
	if test -n "$arg_debug"
	then
		printf "%$(($indent * 2))s%s\n" '' "$*" >&2
	fi
}

# Usage: progress [MSG...]
progress () {
	if test -z "$GIT_QUIET"
	then
		if test -z "$arg_debug"
		then
			# Debug mode is off.
			#
			# Print one progress line that we keep updating (use
			# "\r" to return to the beginning of the line, rather
			# than "\n" to start a new line).  This only really
			# works when stderr is a terminal.
			printf "%s\r" "$*" >&2
		else
			# Debug mode is on.  The `debug` function is regularly
			# printing to stderr.
			#
			# Don't do the one-line-with-"\r" thing, because on a
			# terminal the debug output would overwrite and hide the
			# progress output.  Add a "progress:" prefix to make the
			# progress output and the debug output easy to
			# distinguish.  This ensures maximum readability whether
			# stderr is a terminal or a file.
			printf "progress: %s\n" "$*" >&2
		fi
	fi
}

# Usage: progress_nl
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
progress_nl () {
	assert test $# = 0
	if test -z "$GIT_QUIET" && test -z "$arg_debug"
	then
		printf "\n" >&2
	fi
}

# Usage: assert CMD...
assert () {
	if ! "$@"
	then
		die "assertion failed: $*"
	fi
}

main () {
	if test $# -eq 0
	then
		set -- -h
	fi
	set_args="$(echo "$OPTS_SPEC" | git rev-parse --parseopt -- "$@" || echo exit $?)"
	eval "$set_args"

	# shellcheck disable=SC1091 # don't lint git-sh-setup
	. git-sh-setup

	set -euE -o pipefail

	require_work_tree

	# First figure out the command and whether we use --rejoin, so
	# that we can provide more helpful validation when we do the
	# "real" flag parsing.
	arg_split_rejoin=
	local allow_split=
	local allow_addmerge=
	while test $# -gt 0
	do
		opt="$1"
		shift
		case "$opt" in
			--annotate|-b|-P|-m|--onto|--notree|--remember)
				shift
				;;
			--rejoin)
				arg_split_rejoin=1
				;;
			--no-rejoin)
				arg_split_rejoin=
				;;
			--)
				break
				;;
		esac
	done
	arg_command=$1
	case "$arg_command" in
	add|merge|pull)
		allow_addmerge=1
		;;
	split|push)
		allow_split=1
		allow_addmerge=$arg_split_rejoin
		;;
	*)
		die "Unknown command '$arg_command'"
		;;
	esac
	readonly arg_command
	readonly allow_split
	readonly allow_addmerge
	readonly arg_split_rejoin
	# Reset the arguments array for "real" flag parsing.
	eval "$set_args"

	# Begin "real" flag parsing.
	arg_debug=
	arg_prefix=
	arg_split_branch=
	arg_split_onto=()
	arg_split_notree=()
	arg_split_ignore_joins=
	arg_split_annotate=
	arg_split_remember=()
	arg_addmerge_squash=
	arg_addmerge_message=
	local remember_re='^([^:]+):([^:]+)$'
	while test $# -gt 0
	do
		opt="$1"
		shift

		case "$opt" in
		-q)
			GIT_QUIET=1
			;;
		-d)
			arg_debug=1
			;;
		--annotate)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_annotate="$1"
			shift
			;;
		--no-annotate)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_annotate=
			;;
		-b)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_branch="$1"
			shift
			;;
		-P)
			arg_prefix="${1%/}"
			shift
			;;
		-m)
			test -n "$allow_addmerge" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_addmerge_message="$1"
			shift
			;;
		--no-prefix)
			arg_prefix=
			;;
		--onto)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_onto+=("$(git rev-parse -q --verify "$1^{commit}")") ||
				die "'$1' does not refer to a commit"
			shift
			;;
		--notree)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_notree+=("$(git rev-parse -q --verify "$1^{commit}")") ||
				die "'$1' does not refer to a commit"
			shift
			;;
		--no-onto)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_onto=()
			;;
		--rejoin)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			;;
		--no-rejoin)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			;;
		--ignore-joins)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_ignore_joins=1
			;;
		--no-ignore-joins)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_ignore_joins=
			;;
		--squash)
			test -n "$allow_addmerge" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_addmerge_squash=1
			;;
		--no-squash)
			test -n "$allow_addmerge" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_addmerge_squash=
			;;
		--remember)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			if ! [[ "$1" =~ $remember_re ]]
			then
				die "The '$opt' flag takes an argument of the form 'commit:commit'."
			fi
			arg_split_remember+=("$1")
			shift
			;;
		--)
			break
			;;
		*)
			die "Unexpected option: $opt"
			;;
		esac
	done
	readonly arg_debug
	readonly arg_split_branch
	readonly arg_split_onto
	readonly arg_split_notree
	readonly arg_split_ignore_joins
	readonly arg_split_annotate
	readonly arg_split_remember
	readonly arg_addmerge_squash
	#readonly arg_addmerge_message # we might adjust this if --rejoin
	readonly arg_prefix
	shift

	if test -z "$arg_prefix"
	then
		die "You must provide the --prefix option."
	fi

	case "$arg_command" in
	add)
		test -e "$arg_prefix" &&
			die "prefix '$arg_prefix' already exists."
		;;
	*)
		test -e "$arg_prefix" ||
			die "'$arg_prefix' does not exist; use 'git subtree add'"
		;;
	esac

	dir="$(dirname "$arg_prefix/.")"
	readonly dir

	debug "command: {$arg_command}"
	debug "quiet: {$GIT_QUIET}"
	debug "dir: {$dir}"
	debug "opts: {$*}"

	"cmd_$arg_command" "$@"
}

# Usage: scratchdir_setup
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
scratchdir_setup () {
	assert test $# = 0
	if test "${scratchdir:-}" = "$GIT_DIR/subtree/$$"
	then
		return
	fi
	split_started=false # global
	readonly scratchdir="$GIT_DIR/subtree/$$" # global
	rm -rf "$scratchdir" ||
		die "Can't delete old scratch dir: $scratchdir"
	mkdir -p "$scratchdir/cache" "$scratchdir/attrs" ||
		die "Can't create new scratch dirs: $scratchdir"
	debug "Using scratchdir: $scratchdir"
}

# Usage: var_set KEY VAL
var_set() {
	assert test $# = 2
	local key="$1"
	local val="$2"
	echo "$val" > "$scratchdir/$key"
}

# Usage: var_get KEY
var_get() {
	assert test $# = 1
	local key="$1"
	if test -r "$scratchdir/$key"
	then
		cat "$scratchdir/$key"
	fi
}

# Usage: cache_get [REVS...]
cache_get () {
	assert test -n "$scratchdir"
	local oldrev
	for oldrev in "$@"
	do
		if test -r "$scratchdir/cache/$oldrev"
		then
			cat "$scratchdir/cache/$oldrev"
		fi
	done
}

# Usage: has_attr REV ATTR
has_attr () {
	assert test $# = 2
	local rev="$1"
	local attr="$2"
	test -r "$scratchdir/attrs/$rev" && grep -qFx "$attr" "$scratchdir/attrs/$rev"
}

# Usage: attr_set COMMIT SUBTREE_COMMIT
attr_set () {
	assert test $# = 2
	local key="$1"
	local val="$2"
	debug "setting commit:$key += attr:$val"
	echo "$val" >> "$scratchdir/attrs/$key"
}

# Usage: cache_set_internal COMMIT SUBTREE_COMMIT
#
# See cache_set.
cache_set_internal () {
	assert test $# = 2
	assert test -n "$scratchdir"
	local key="$1"
	local val="$2"
	debug "caching commit:$key = subtree_commit:$val"
	if test -e "$scratchdir/cache/$key"
	then
		local oldval
		oldval=$(cat "$scratchdir/cache/$key")
		if test "$oldval" = "$val"
		then
			debug "  already cached: commit:$key = subtree_commit:$val"
			cache_set_existed=true
			return
		elif test "$oldval" = counted
		then
			debug "  overwriting existing subtree_commit:counted"
		else
			die "caching commit:$key = subtree_commit:$val conflicts with existing subtree_commit:$oldval!"
		fi
	fi
	if $split_started && has_attr "$key" redo && test "$(cache_get "$val")" != "$val"
	then
		# shellcheck disable=SC2086 # $split_redoing is intentionally unquoted
		die "$(printf '%s\n' \
		    "commit:$key has already been split, but when re-doing the split we got a different result: original_result=unknown new_result=commit:$val" \
		    '  redo stack:' \
		    "$(printf '    %s\n' ${split_redoing})" \
		    "If you've recently changed your subtree settings (like changing --annotate=)," \
		    "then you'll need to help git-subtree out by supplying some --remember= flags." \
		    "Otherwise, this is a bug in git-subtree."
		    )"
	fi
	echo "$val" >"$scratchdir/cache/$key"
}


# Usage: cache_set COMMIT SUBTREE_COMMIT
#
# Store a COMMIT->SUBTREE_COMMIT mapping.  COMMIT may be:
#  - a subtree commit (in which case the mapping is the identity)
#  - a mainline commit
#  - a squashed subtree commit
# mainline commit, or a subtree commit
cache_set () {
	assert test $# = 2
	local key="$1"
	local val="$2"

	local cache_set_existed=false

	cache_set_internal "$key" "$val"

	if test "$cache_set_existed" = true
	then
		return
	fi

	local indent=$((indent + 1))
	case "$val" in
	'counted')
		:
		;;
	'notree')
		:
		;;
	*)
		# If we've identified a subtree-commit, then also
		# record its ancestors as being subtree commits.  If
		# we haven't started the split yet, then hold off for
		# now; we'll do this in a big batch before starting.
		if $split_started
		then
			local parents
			parents=$(git rev-parse "$val^@") ||
				die "could not read parents of commit '$val'"
			local parent
			for parent in $parents
			do
				cache_set "$parent" "$parent"
			done
		fi
		;;
	esac
}

# Usage: rev_exists REV
rev_exists () {
	assert test $# = 1
	if git rev-parse "$1" >/dev/null 2>&1
	then
		return 0
	else
		return 1
	fi
}

# Usage: find_latest_squash REVS...
#
# Print a pair "A B", where:
# - A is the latest in-mainline-subtree-commit (either a real
#   subtree-commit, or a squashed subtree-commit)
# - B is the corresponding real subtree-commit (just A again, unless
#   --squash)
find_latest_squash () {
	assert test $# -gt 0
	debug "Pre-loading cache with latest squash ($dir)..."
	local indent=$(($indent + 1))

	local sq=
	local main=
	local sub=
	local a b junk
	git log --grep="^git-subtree-dir: $dir/*\$" \
		--no-show-signature --pretty=format:'START %H%n%s%n%n%b%nEND%n' "$@" |
	while read -r a b junk
	do
		case "$a" in
		START)
			sq="$b"
			;;
		git-subtree-mainline:)
			main="$b"
			;;
		git-subtree-split:)
			sub="$(git rev-parse -q --verify "$b^{commit}")" ||
				die "could not rev-parse 'git-subtree-split: $b' from commit '$sq'"
			;;
		END)
			if test -z "$sub"
			then
				debug "prior malformed commit: $sq"
			else
				if test -z "$main"
				then
					debug "prior --squash: $sq"
					debug "  git-subtree-split: '$sub'"
				else
					debug "prior --rejoin: $sq"
					debug "  git-subtree-mainline: '$main'"
					debug "  git-subtree-split:    '$sub'"
					# a rejoin commit?
					# Pretend its sub was a squash.
					sq="$(git rev-parse -q --verify "$sq^2")" ||
						die "could not get second parent of --rejoin merge commit '$sq'"
				fi
				debug "Squash found: $sq $sub"
				echo "$sq" "$sub"
				cat >/dev/null # drain `git log`, don't SIGPIPE it (we have pipefail set)
				break
			fi
			sq=
			main=
			sub=
			;;
		esac
	done || exit $?
}

# Usage: split_process_annotated_commits REV
split_process_annotated_commits () {
	assert test $# = 1
	local rev="$1"
	debug "Pre-loading cache with prior annotated commits..."
	local indent=$(($indent + 1))

	local grep_format="^git-subtree-dir: $dir/*\$"
	if test -n "$arg_split_ignore_joins"
	then
		grep_format="^Add '$dir/' from commit '"
	fi

	# An 'add' (without '--squash') looks like:
	#
	#     ,-mainline
	#     | ,-subtree
	#     v v
	#     H     < the commit created by `git subtree add`
	#     |\
	#     M S
	#     : :
	#
	# Where "H" has a commit message that says:
	#
	#   git-subtree-dir: $dir
	#   git-subtree-mainline: $M
	#   git-subtree-split: $S

	# A 'merge' looks like a regular git merge.  There are no
	# special markers in the commit message (BTW, it's absolutely
	# stupid that this doesn't look like 'add' and 'split
	# --rejoin').

	# A 'split --rejoin' (with or without '--squash') looks like:
	#
	#     ,-mainline
	#     | ,-subtree
	#     v v
	#     H     < the commit created by `git subtree split --rejoin`
	#     |\
	#     B B'
	#     | |
	#     A A'
	#     | |
	#     o |
	#     |\|
	#     o o
	#     : :
	#
	# Where "H" has a commit message that says:
	#
	#   git-subtree-dir: $dir
	#   git-subtree-mainline: $B
	#   git-subtree-split: $B'

	# A '--squash' operation looks like:
	#
	#     ,-mainline
	#     | ,-squashed-subtree
	#     | |  ,-subtree
	#     v v  v
	#     H
	#     |\
	#     o S' S
	#     : :  :
	#
	# Where "S'" has a commit message that says:
	#
	#   git-subtree-dir: $dir
	#   git-subtree-split: $S
	#
	# If the operation was an 'add' or a 'merge', then "H" looks
	# like a regular commit with no special markers.  If the
	# operation was a 'split --rejoin', then "H" looks as
	# described for 'split --rejoin' above.

	local count=0
	progress "Pre-loading cache with prior annotated commits... $count"
	local sq=
	local main=
	local sub=
	local a b junk
	git log --grep="$grep_format" \
		--no-show-signature --pretty=format:'START %H%n%s%n%n%b%nEND%n' "$rev" |
	while read -r a b junk
	do
		case "$a" in
		START)
			sq="$b"
			;;
		git-subtree-mainline:)
			main="$b"
			;;
		git-subtree-split:)
			sub="$(git rev-parse -q --verify "$b^{commit}")" ||
				die "could not rev-parse 'git-subtree-split: $b' from commit '$sq'"
			;;
		END)
			if test -z "$sub"
			then
				debug "prior malformed commit: $sq"
			else
				if test -z "$main"
				then
					debug "prior --squash: $sq"
					debug "  git-subtree-split: '$sub'"
					cache_set "$sq" "$sub"
				else
					local mainline_tree split_tree
					mainline_tree=$(subtree_for_commit "$main")
					split_tree=$(toptree_for_commit "$sub")

					if test -z "$mainline_tree"
					then
						debug "prior add: $sq"
						debug "  git-subtree-mainline: '$main'"
						debug "  git-subtree-split:    '$sub'"
						cache_set "$main" notree
					elif test "$mainline_tree" = "$split_tree"
					then
						debug "prior --rejoin: $sq"
						debug "  git-subtree-mainline: '$main'"
						debug "  git-subtree-split:    '$sub'"
						cache_set "$main" "$sub"
					else
						# `git subtree merge` doesn't currently do this, but it wouldn't be a
						# bad idea.
						debug "prior merge: $sq"
						debug "  git-subtree-mainline: '$main'"
						debug "  git-subtree-split:    '$sub'"
					fi
					cache_set "$sub" "$sub"
				fi
			fi
			sq=
			main=
			sub=
			count=$(($count + 1))
			progress "Pre-loading cache with prior annotated commits... $count"
			;;
		esac
	done || exit $?
}

# Usage: copy_commit REV TREE FLAGS_STR
copy_commit () {
	assert test $# = 3
	# We're going to set some environment vars here, so
	# do it in a subshell to get rid of them safely later
	debug copy_commit "{$1}" "{$2}" "{$3}"
	git log -1 --no-show-signature --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD%n%B' "$1" |
	(
		read -r GIT_AUTHOR_NAME
		read -r GIT_AUTHOR_EMAIL
		read -r GIT_AUTHOR_DATE
		read -r GIT_COMMITTER_NAME
		read -r GIT_COMMITTER_EMAIL
		read -r GIT_COMMITTER_DATE
		export  GIT_AUTHOR_NAME \
			GIT_AUTHOR_EMAIL \
			GIT_AUTHOR_DATE \
			GIT_COMMITTER_NAME \
			GIT_COMMITTER_EMAIL \
			GIT_COMMITTER_DATE
		(
			printf "%s" "$arg_split_annotate"
			cat
		) | (
			# shellcheck disable=SC2086 # $3 is intentionally unquoted
			git commit-tree "$2" $3  # reads the rest of stdin
		)
	) || die "Can't copy commit $1"
}

# Usage: add_msg
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
add_msg () {
	assert test $# = 0

	local latest_mainline latest_split
	latest_mainline=$(var_get latest_mainline) || exit $?
	latest_split=$(var_get latest_split) || exit $?

	local commit_message
	if test -n "$arg_addmerge_message"
	then
		commit_message="$arg_addmerge_message"
	else
		commit_message="Add '$dir/' from commit '$latest_split'"
	fi
	if test -n "$arg_split_rejoin"
	then
		# If this is from a --rejoin, then rejoin_msg has
		# already inserted the `git-subtree-xxx:` tags
		echo "$commit_message"
		return
	fi
	cat <<-EOF
		$commit_message

		git-subtree-dir: $dir
		git-subtree-mainline: $latest_mainline
		git-subtree-split: $latest_split
	EOF
}

# Usage: add_squashed_msg
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
add_squashed_msg () {
	assert test $# = 0

	local latest_split
	latest_split=$(var_get latest_split) || exit $?

	if test -n "$arg_addmerge_message"
	then
		echo "$arg_addmerge_message"
	else
		echo "Merge commit '$latest_split' as '$dir'"
	fi
}

# Usage: rejoin_msg
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
rejoin_msg () {
	assert test $# = 0

	local latest_mainline latest_split
	latest_mainline=$(var_get latest_mainline) || exit $?
	latest_split=$(var_get latest_split) || exit $?

	local commit_message
	if test -n "$arg_addmerge_message"
	then
		commit_message="$arg_addmerge_message"
	else
		commit_message="Split '$dir/' into commit '$latest_split'"
	fi
	cat <<-EOF
		$commit_message

		git-subtree-dir: $dir
		git-subtree-mainline: $latest_mainline
		git-subtree-split: $latest_split
	EOF
}

# Usage: squash_msg OLD_SUBTREE_COMMIT NEW_SUBTREE_COMMIT
squash_msg () {
	assert test $# = 2
	local oldsub="$1"
	local newsub="$2"

	local oldsub_short newsub_short
	newsub_short=$(git rev-parse --short "$newsub")

	if test -n "$oldsub"
	then
		oldsub_short=$(git rev-parse --short "$oldsub")
		echo "Squashed '$dir/' changes from $oldsub_short..$newsub_short"
		echo
		git log --no-show-signature --pretty=tformat:'%h %s' "$oldsub..$newsub"
		git log --no-show-signature --pretty=tformat:'REVERT: %h %s' "$newsub..$oldsub"
	else
		echo "Squashed '$dir/' content from commit $newsub_short"
	fi

	echo
	echo "git-subtree-dir: $dir"
	echo "git-subtree-split: $newsub"
}

# Usage: toptree_for_commit COMMIT
toptree_for_commit () {
	assert test $# = 1
	local commit="$1"
	git rev-parse -q --verify "$commit^{tree}" ||
		die "could not resolve tree for commit '$commit'"
}

# Usage: subtree_for_commit COMMIT
subtree_for_commit () {
	assert test $# = 1
	local commit="$1"
	local mode type tree name
	# shellcheck disable=SC2034 # we don't use the 'mode' field
	git ls-tree "$commit" -- "$dir" |
	while read -r mode type tree name
	do
		assert test "$name" = "$dir"
		assert test "$type" = "tree" -o "$type" = "commit"
		if test "$type" != 'tree'
		then
			# ignore submodules and other not-a-plain-directory things
			continue
		fi
		echo "$tree"
		cat >/dev/null # drain `git ls-tree`, don't SIGPIPE it (we have pipefail set)
		break
	done || exit $?
}

# Usage: tree_changed TREE [PARENTS...]
tree_changed () {
	assert test $# -gt 0
	local tree=$1
	shift
	if test $# -ne 1
	then
		return 0   # weird parents, consider it changed
	else
		local ptree
		ptree=$(toptree_for_commit "$1") || exit $?
		if test "$ptree" != "$tree"
		then
			return 0   # changed
		else
			return 1   # not changed
		fi
	fi
}

# Usage: new_squash_commit OLD_SQUASHED_COMMIT OLD_NONSQUASHED_COMMIT NEW_NONSQUASHED_COMMIT
new_squash_commit () {
	assert test $# = 3
	local old="$1"
	local oldsub="$2"
	local newsub="$3"

	local tree
	tree=$(toptree_for_commit "$newsub") || exit $?
	if test -n "$old"
	then
		squash_msg "$oldsub" "$newsub" |
		git commit-tree "$tree" -p "$old" || exit $?
	else
		squash_msg "" "$newsub" |
		git commit-tree "$tree" || exit $?
	fi
}

# Usage: copy_or_skip REV TREE NEWPARENTS
copy_or_skip () {
	assert test $# = 3
	local rev="$1"
	local tree="$2"
	local newparents="$3"
	assert test -n "$tree"

	local identical=
	local nonidentical=
	local p=
	local gotparents=
	local copycommit=
	local parent ptree
	# shellcheck disable=SC2086 # $newparents is intentionally unquoted
	for parent in $newparents
	do
		ptree=$(toptree_for_commit "$parent") || exit $?
		test -z "$ptree" && continue
		if test "$ptree" = "$tree"
		then
			# an identical parent could be used in place of this rev.
			if test -n "$identical"
			then
				# if a previous identical parent was found, check whether
				# one is already an ancestor of the other
				local mergebase
				mergebase=$(git merge-base "$identical" "$parent")
				if test "$identical" = "$mergebase"
				then
					# current identical commit is an ancestor of parent
					identical="$parent"
				elif test "$parent" != "$mergebase"
				then
					# no common history; commit must be copied
					copycommit=1
				fi
			else
				# first identical parent detected
				identical="$parent"
			fi
		else
			nonidentical="$parent"
		fi

		# sometimes both old parents map to the same newparent;
		# eliminate duplicates
		local is_new=1
		local gp
		for gp in $gotparents
		do
			if test "$gp" = "$parent"
			then
				is_new=
				break
			fi
		done
		if test -n "$is_new"
		then
			gotparents="$gotparents $parent"
			p="$p -p $parent"
		fi
	done

	if test -n "$identical" && test -n "$nonidentical"
	then
		local extras
		extras=$(git rev-list --count "$identical..$nonidentical")
		if test "$extras" -ne 0
		then
			# we need to preserve history along the other branch
			copycommit=1
		fi
	fi
	if test -n "$identical" && test -z "$copycommit"
	then
		echo "skip $identical"
	else
		copy_commit "$rev" "$tree" "$p" || exit $?
	fi
}

# Usage: ensure_clean
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
ensure_clean () {
	assert test $# = 0
	if ! git diff-index HEAD --exit-code --quiet 2>&1
	then
		die "Working tree has modifications.  Cannot add."
	fi
	if ! git diff-index --cached HEAD --exit-code --quiet 2>&1
	then
		die "Index has modifications.  Cannot add."
	fi
}

# Usage: ensure_valid_ref_format REF
ensure_valid_ref_format () {
	assert test $# = 1
	git check-ref-format "$1" ||
		die "'$1' does not look like a ref"
}

# Usage: split_list_relevant_parents REV
split_list_relevant_parents () {
	assert test $# = 1
	local rev="$1"

	local parents
	parents=$(git rev-parse "$rev^@") ||
		die "could not read parents of commit '$rev'"

	# If  (1.a) this is a simple 2-way merge,
	# and (1.b) one of the parents has the subtree,
	# and (1.c) the other parent does hot have the subtree,
	# then:
	#
	#  it is reasonably safe to assume that this a subtree-merge
	#  commit.
	#
	# If (1) is satisfied,
	# and (2.a) the subtree-directory in mainline parent is identical to in the merge,
	# and (2.b) the subtree parent is identical to the subtree-directory in the merge,
	# then:
	#
	#  it is reasonably safe to assume that the merge is
	#  specifically a --rejoin, and we can avoid crawling the
	#  history more.
	#
	# On the other hand,
	# if (1) is satisfied,
	# and (3.a) the subtree-directory in mainline parent is identical to in the merge,
	# and (3.b) the subtree parent is not identical to the subtree-directory in the merge,
	# and (3.c)
	#   either (3.c.1) the merge differs from the mainline parent,
	#   and/or (3.c.2) split_classify_commit doesn't classify the subtree parent as being part of our subtree ('split' or 'squash'),
	# then:
	#
	#  it is reasonably safe to assume that the merge is for a
	#  *different subtree* than the subtree-directory that we're
	#  splitting, and that we should ignore the subtree parent.
	#
	#  Now, (3.c) merits some explanation:
	#   - (3.c.1) indicates that only things outside of our
	#     subtree changes, and since (1) tells us that this is a
	#     subtree-merge, then it must obviously be a different
	#     subtree.
	#   - (3.c.2) if we can't get an answer from the merge data
	#     (as !3.c.1 would indicate), then we must get our answer
	#     from inspecting the commit itself, and that's what
	#     split_classsify_commit does.

	# shellcheck disable=SC2086 # $parents is intentionally unquoted
	set -- $parents
	if test $# = 2
	then
		local p1_subtree p2_subtree
		p1_subtree=$(subtree_for_commit "$1")
		p2_subtree=$(subtree_for_commit "$2")
		local mainline='' mainline_subtree subtree
		if test -n "$p1_subtree" && test -z "$p2_subtree"
		then
			mainline=$1
			mainline_subtree=$p1_subtree
			subtree=$2
		elif test -z "$p1_subtree" && test -n "$p2_subtree"
		then
			mainline=$2
			mainline_subtree=$p2_subtree
			subtree=$1
		fi
		if test -n "$mainline" # condition (1)
		then
			# OK, condition (1) is satisfied
			debug "commit $rev is a subtree-merge"
			local merge_subtree
			merge_subtree=$(subtree_for_commit "$rev")
			if test "$merge_subtree" = "$mainline_subtree" # condition (2.a)=(3.a)
			then
				local classification
				classification=$(split_classify_commit "$subtree")

				local subtree_toptree
				subtree_toptree=$(toptree_for_commit "$subtree")
				if test "$merge_subtree" = "$subtree_toptree" # condition (2.b)
				then
					# OK, condition (2) is satisfied
					debug "commit $rev is is a --rejoin merge"
					case "$classification" in
					split)
						cache_set "$rev" "$subtree"
						return
						;;
					squash)
						echo "$subtree"
						return
						;;
					*)
						die "bad classification split-or-squash $subtree: $classification"
						;;
					esac
				else # condition (3.b)
					local merge_toptree mainline_toptree
					merge_toptree=$(toptree_for_commit "$rev")
					mainline_toptree=$(toptree_for_commit "$mainline")

					if test "$merge_toptree" != "$mainline_toptree" || { test "$classification" != 'split' && test "$classification" != 'squash'; } # condition (3.c)
					then
						# OK, condition (3) is satisfied
						debug "commit $rev is a merge for a different subtree"
						echo "$mainline"
						return
					fi
				fi
			fi
		fi
	fi
	echo "$@" # $@ is set to $parents
}

# Usage: split_count_commits REV
#
# Increments the `split_max` variable, stores the value "counted" in
# to the cache for counted commits.
split_count_commits () {
	assert test $# = 1
	local rev="$1"

	local cached
	cached=$(cache_get "$rev") || exit $?
	if test -n "$cached"
	then
		return
	fi

	debug "Counting commit: $rev"
	local indent=$(($indent + 1))

	cache_set "$rev" counted
	split_max=$(($split_max + 1)) # in parent scope
	progress "Counting commits... $split_max"

	local parents
	parents=$(split_list_relevant_parents "$rev") || exit $?
	local parent
	for parent in $parents
	do
		split_count_commits "$parent"
	done
}

# Usage: printf '%s\n' POSSIBLE_SIBLINGS... | reduce_commits
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
reduce_commits() {
	assert test $# = 0

	# The main constraint that this function solves is that we
	# might have a list of too many commits to pass as arguments
	# to `git merge-base` without overflowing ARG_MAX.  So we're
	# going to batch the commits in to groups, and do a janky
	# serialized map/reduce to shrink that list as much as
	# possible using `git merge-base --independent`.

	local tmpdir
	tmpdir="$(mktemp -d -t git-subtree.XXXXXXXXXX)"

	# First (no-op) iteration
	touch "$tmpdir/in"
	# The 'grep .' is for versions of xargs (GNU and OpenBSD) that
	# run the command on empty input.  We use grep instead of
	# passing xargs the -r/--no-run-if-empty option because some
	# versions of xargs (macOS) don't have that option.
	xargs printf '%s\n' | { grep . || true; } >"$tmpdir/out"

	# Check for the trivial case
	if test "$(wc -l <"$tmpdir/out")" -le 1
	then
		cat "$tmpdir/out"
		rm -rf -- "$tmpdir"
		return
	fi

	# Do we need to run again?
	#  (first iteration: yes, unless the input was empty)
	#  (later iterations: possibly, if there were multiple batches
	#   and things can reduce across batches)
	while test "$(wc -l <"$tmpdir/out")" -ne "$(wc -l <"$tmpdir/in")"
	do
		mv "$tmpdir/out" "$tmpdir/in"
		<"$tmpdir/in" xargs git merge-base --independent -- >"$tmpdir/out.tmp" ||
			die "reduce_commits: 'git merge-base --independent' failed"
		<"$tmpdir/out.tmp" sort --random-sort --unique >"$tmpdir/out"
	done

	LC_COLLATE=C sort <"$tmpdir/out"
	rm -rf -- "$tmpdir"
}

# Usage: printf '%s\n' POSSIBLE_SIBLINGS... | is_related COMMIT
is_related() {
	assert test $# = 1

	local tmpfile
	tmpfile="$(mktemp -t git-subtree.XXXXXXXXXX)"

	reduce_commits >"$tmpfile"
	local result=1
	while read -r other
	do
		if git merge-base -- "$rev" "$other" >/dev/null
		then
			result=0
			break
		fi
	done <"$tmpfile"
	rm -- "$tmpfile"
	return "$result"
}

# Usage: split_classify_commit REV
split_classify_commit () {
	assert test $# = 1
	local rev="$1"

	local msg m_dir='' m_mainline='' m_split=''
	msg=$(git show --no-patch --no-show-signature --pretty=format:'%B' "$rev") || exit $?
	local a b junk
	while read -r a b junk
	do
		case "$a" in
		git-subtree-dir:)
			# shellcheck disable=SC2001 # this would be clunky to do without sed
			m_dir="$(sed 's,/*$,,' <<<"$b")"
			;;
		git-subtree-mainline:)
			m_mainline="$b"
			;;
		git-subtree-split:)
			# Don't bother with resolving "$b^{commit}"`
			# here, we just care about empty/non-empty.
			m_split="$b"
			;;
		esac
	done <<<"$msg"
	if test "$m_dir" = "$dir" && test -n "$m_split"
	then
		if test -z "$m_mainline"
		then
			# Prior --squash
			echo 'squash'
			return
		else
			# Prior --rejoin
			if test -z "$arg_split_ignore_joins"
			then
				echo 'mainline:tree'
				return
			fi
		fi
	fi

	local tree
	tree=$(subtree_for_commit "$rev") || exit $?
	# shellcheck disable=SC2046 # $(grep ...) in the 'elif' is intentionally unquoted
	if test -n "$tree"
	then
		# It contains the subtree path; presume it is a
		# mainline commit that contains the subtree.
		echo 'mainline:tree'
	elif { grep -rhvx -e notree -e counted "$scratchdir/cache" || true; } | is_related "$rev"
	then
		# It has an ancestor that is known to be a subtree
		# commit; assume it's a subtree-commit.
		echo 'split'
	else
		echo 'mainline:notree'
	fi
}

# Usage: split_process_commit REV
split_process_commit () {
	assert test $# = 1
	local rev="$1"

	local cached
	cached=$(cache_get "$rev") || exit $?
	case "$cached" in
	'')
		die "processing unexpected commit: $rev"
		;;
	counted)
		# proceed
		;;
	*)
		# already processed
		return
		;;
	esac

	debug "Processing commit: $rev"
	local indent=$(($indent + 1))
	if has_attr "$rev" redo
	then
		debug "(redoing previous split)"
		local split_redoing="$split_redoing $rev"
	fi

	local parents
	parents=$(split_list_relevant_parents "$rev") || exit $?
	local parent
	for parent in $parents
	do
		split_process_commit "$parent"
	done

	debug "processed parents of $rev, processing commit itself..."

	local classification
	classification=$(split_classify_commit "$rev") || exit $?
	debug "classification: {$classification}"
	case "$classification" in
	mainline:tree)
		# shellcheck disable=SC2086
		debug parents: $parents

		local newparents
		# shellcheck disable=SC2086
		newparents=$(cache_get $parents | grep -vx notree || true)
		# shellcheck disable=SC2086
		debug newparents: $newparents

		local tree
		tree=$(subtree_for_commit "$rev") || exit $?

		local newrev
		split_created_from=$(($split_created_from + 1)) # in parent scope
		newrev=$(copy_or_skip "$rev" "$tree" "$newparents") || exit $?
		# shellcheck disable=SC2086 # $newrev is intentionally unquoted
		set -- $newrev
		if test "$1" = skip
		then
			newrev=$2
		else
			split_created_to=$(($split_created_to + 1)) # in parent scope
		fi

		debug "newrev: $newrev"
		cache_set "$rev" "$newrev"
		var_set latest_split "$newrev"
		var_set latest_mainline "$rev"
		;;
	mainline:notree)
		cache_set "$rev" notree
		var_set latest_mainline "$rev"
		;;
	split)
		debug "subtree"
		cache_set "$rev" "$rev"
		var_set latest_split "$rev"
		;;
	squash)
		debug "squash"
		local a b junk
		git show --no-patch --no-show-signature --pretty=format:'%B' "$rev" | while read -r a b junk
		do
			if test "$a" = 'git-subtree-split:'
			then
				cache_set "$rev" "$b"
				var_set latest_split "$b"
			fi
		done || exit $?
		;;
	*)
		die "bad classification of $rev: $classification"
		;;
	esac

	split_processed=$(($split_processed + 1)) # in parent scope
	progress "Processing commits... ${split_processed}/${split_max} (created: ${split_created_from}->${split_created_to})"
}

# Usage: split_remember BEFORE AFTER
split_remember () {
	assert test $# = 2
	local before after
	before=$(git rev-parse -q --verify "$1^{commit}") ||
		die "'$1' does not refer to a commit"
	after=$(git rev-parse -q --verify "$2^{commit}") ||
		die "'$2' does not refer to a commit"

	# validate: trees
	local before_tree after_tree
	before_tree=$(subtree_for_commit "$before") ||
		die "Commit '${before}' does not have a '${dir}' directory."
	after_tree=$(toptree_for_commit "$after") ||
		die "Could not get root directory for subtree commit '${after}'."
	test "$before_tree" = "$after_tree" ||
		die "Before-commit '${before}' and after-commit '${after}' do not have trees that go together."

	# validate: messages
	local before_msg after_msg
	# The 'echo x' is to make sure we're robust to matching trailing newlines.
	before_msg=$(git log -1 --no-show-signature --pretty=format:'%B' "$before"; echo x)
	after_msg=$(git log -1 --no-show-signature --pretty=format:'%B' "$after"; echo x)
	# Require that $after_msg have $before_msg as a suffix--we allow other prefixes to
	# allow varying --annotate flags.
	[[ "$after_msg" = *"$before_msg" ]] ||
		die "Before-commit '${before}' and after-commit '${after}' do not have commit messages that go together."

	# validate: other metadata
	local before_msg after_msg
	# author_{name,email,date}, committer_{name,email,date}
	before_metadata=$(git log -1 --no-show-signature --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD' "$before")
	after_metadata=$(git log -1 --no-show-signature --pretty=format:'%an%n%ae%n%aD%n%cn%n%ce%n%cD' "$after")
	test "$before_metadata" = "$after_metadata" ||
		die "Before-commit '${before}' and after-commit '${after}' do not have committer/author info that go together."

	# OK, remember that
	cache_set "$before" "$after"
}

# Usage: cmd_add REV
#    Or: cmd_add REPOSITORY REF
cmd_add () {
	debug

	ensure_clean

	if test $# -eq 1
	then
		git rev-parse -q --verify "$1^{commit}" >/dev/null ||
			die "'$1' does not refer to a commit"

		cmd_add_commit "$@"

	elif test $# -eq 2
	then
		# Technically we could accept a refspec here but we're
		# just going to turn around and add FETCH_HEAD under the
		# specified directory.  Allowing a refspec might be
		# misleading because we won't do anything with any other
		# branches fetched via the refspec.
		ensure_valid_ref_format "refs/heads/$2"

		cmd_add_repository "$@"
	else
		say >&2 "error: parameters were '$*'"
		die "Provide either a commit or a repository and commit."
	fi
}

# Usage: cmd_add_repository REPOSITORY REFSPEC
cmd_add_repository () {
	assert test $# = 2
	echo "git fetch" "$@"
	git fetch "$@" || exit $?
	cmd_add_commit FETCH_HEAD
}

# Usage: cmd_add_commit REV
cmd_add_commit () {
	# The rev has already been validated by cmd_add(), we just
	# need to normalize it.
	assert test $# = 1
	local rev
	rev=$(git rev-parse -q --verify "$1^{commit}") ||
		die "'$1' does not refer to a commit"

	debug "Adding $dir as '$rev'..."
	if test -z "$arg_split_rejoin"
	then
		# Only bother doing this if this is a genuine 'add',
		# not a synthetic 'add' from '--rejoin'.
		git read-tree --prefix="$dir" "$rev" || exit $?
	fi
	git checkout -- "$dir" || exit $?
	tree=$(git write-tree) || exit $?

	headrev=$(git rev-parse HEAD) ||
		die "'HEAD' does not refer to a commit"
	if test -n "$headrev" && test "$headrev" != "$rev"
	then
		headp="-p $headrev"
	else
		headp=
	fi

	scratchdir_setup
	var_set latest_split "$rev"
	var_set latest_mainline "$headrev"

	if test -n "$arg_addmerge_squash"
	then
		rev=$(new_squash_commit "" "" "$rev") || exit $?
		# shellcheck disable=SC2086 # $headp is intentionally unquoted
		commit=$(add_squashed_msg |
			git commit-tree "$tree" $headp -p "$rev") || exit $?
	else
		revp=$(peel_committish "$rev") || exit $?
		# shellcheck disable=SC2086 # $headp is intentionally unquoted
		commit=$(add_msg |
			git commit-tree "$tree" $headp -p "$revp") || exit $?
	fi
	git reset "$commit" || exit $?

	say >&2 "Added dir '$dir'"
}

# Usage: cmd_split [REV]
cmd_split () {
	local rev
	case $# in
	0)
		rev=$(git rev-parse HEAD)
		;;
	1)
		rev=$(git rev-parse -q --verify "$1^{commit}") ||
			die "'$1' does not refer to a commit"
		;;
	*)
		die "You must provide exactly one revision.  Got: '$*'"
		;;
	esac
	debug "rev: {$rev}"
	debug

	if test -n "$arg_split_rejoin"
	then
		ensure_clean
	fi

	debug "Splitting $dir..."
	scratchdir_setup

	progress "Pre-loading cache with --remember'ed commits... 0"
	local i=0 remember before after
	for remember in "${arg_split_remember[@]}"
	do
		IFS=: read -r before after <<<"$remember"
		split_remember "$before" "$after"
		i=$(($i + 1))
		progress "Pre-loading cache with --remember'ed commits... $i"
	done
	progress_nl

	progress "Pre-loading cache with --onto commits... 0"
	local i=0 onto
	for onto in "${arg_split_onto[@]}"
	do
		debug "cli --onto: $onto"
		cache_set "$onto" "$onto"
		i=$(($i + 1))
		progress "Pre-loading cache with --onto commits... $i"
	done
	progress_nl

	progress "Pre-loading cache with --notree commits... 0"
	local i=0 notree
	for notree in "${arg_split_notree[@]}"
	do
		debug "cli --notree: $notree"
		cache_set "$notree" notree
		i=$(($i + 1))
		progress "Pre-loading cache with --notree commits... $i"
	done
	progress_nl

	# This will pre-load the cache with info from commits with
	# "subtree-XXX: YYY" annotations in the commit message.
	progress "Pre-loading cache with prior annotated commits..."
	split_process_annotated_commits "$rev"
	progress_nl

	progress "De-normalizing cache of split commits..."
	id_parents=()
	redo_parents=()
	for file in "$scratchdir/cache"/*
	do
		key="${file##*/}"
		if test "$key" = '*'
		then
			continue
		fi
		val="$(cache_get "$key")" || exit $?
		if test "$val" = notree
		then
			continue
		fi
		if test "$(cache_get "$key")" = "$key"
		then
			id_parents+=("$key")
		else
			redo_parents+=("$key")
		fi
	done
	if test "${#id_parents[@]}" -gt 0
	then
		git rev-list "${id_parents[@]}" | while read -r ancestor
		do
			cache_set_internal "$ancestor" "$ancestor"
		done || exit $?
	fi
	if test "${#redo_parents[@]}" -gt 0
	then
		git rev-list "${redo_parents[@]}" | while read -r ancestor
		do
			if test -z "$(cache_get "$ancestor")"
			then
				attr_set "$ancestor" redo
			fi
		done || exit $?
	fi
	progress_nl

	progress 'Counting commits...'
	local split_max=0
	split_count_commits "$rev"
	readonly split_max
	progress_nl

	split_started=true # global
	local split_processed=0
	local split_created_from=0
	local split_created_to=0
	local split_redoing=''
	progress "Processing commits... ${split_processed}/${split_max} (created: ${split_created_from}->${split_created_to})"
	split_process_commit "$rev"
	progress_nl

	progress 'Done'
	progress_nl

	local latest_split
	latest_split=$(var_get latest_split) || exit $?
	if test -z "$latest_split"
	then
		say >&2 "No new revisions were found"
		latest_split=$(cache_get "$rev") || exit $?
		cache_set latest_split "$latest_split"
	elif test -n "$arg_split_rejoin"
	then
		debug "Merging split branch into HEAD..."
		arg_addmerge_message="$(rejoin_msg)" || exit $?
		local latest_squash
		latest_squash=$(find_latest_squash "$rev") || exit $?
		if test -z "$latest_squash"
		then
			cmd_add "$latest_split" >&2 || exit $?
		else
			cmd_merge "$latest_split" >&2 || exit $?
		fi
	fi

	if test -n "$arg_split_branch"
	then
		local action
		if rev_exists "refs/heads/$arg_split_branch"
		then
			if ! git merge-base --is-ancestor "$arg_split_branch" "$latest_split"
			then
				die "Branch '$arg_split_branch' is not an ancestor of commit '$latest_split'."
			fi
			action='Updated'
		else
			action='Created'
		fi
		git update-ref -m 'subtree split' \
			"refs/heads/$arg_split_branch" "$latest_split" || exit $?
		say >&2 "$action branch '$arg_split_branch'"
	fi
	echo "$latest_split"
	exit 0
}

# Usage: cmd_merge REV
cmd_merge () {
	test $# -eq 1 ||
		die "You must provide exactly one revision.  Got: '$*'"
	local rev
	rev=$(git rev-parse -q --verify "$1^{commit}") ||
		die "'$1' does not refer to a commit"
	debug "rev: {$rev}"
	debug

	ensure_clean

	if test -n "$arg_addmerge_squash"
	then
		local first_split
		first_split="$(find_latest_squash HEAD)" || exit $?
		if test -z "$first_split"
		then
			die "Can't squash-merge: '$dir' was never added."
		fi
		# shellcheck disable=SC2086 # $first_split is intentionally unquoted
		set -- $first_split
		assert test $# = 2
		local old=$1
		local sub=$2
		if test "$sub" = "$rev"
		then
			say >&2 "Subtree is already at commit $rev."
			exit 0
		fi
		local new
		new=$(new_squash_commit "$old" "$sub" "$rev") || exit $?
		debug "New squash commit: $new"
		rev="$new"
	fi

	if test -n "$arg_addmerge_message"
	then
		git merge -Xsubtree="$arg_prefix" \
			--message="$arg_addmerge_message" "$rev"
	else
		git merge -Xsubtree="$arg_prefix" "$rev"
	fi
}

# Usage: cmd_pull REPOSITORY REMOTEREF
cmd_pull () {
	if test $# -ne 2
	then
		die "You must provide <repository> <ref>"
	fi
	ensure_clean
	ensure_valid_ref_format "refs/heads/$2"
	debug

	git fetch "$@" || exit $?
	cmd_merge FETCH_HEAD
}

# Usage: cmd_push REPOSITORY [+][LOCALREV:]REMOTEREF
cmd_push () {
	if test $# -ne 2
	then
		die "You must provide <repository> <refspec>"
	fi
	if test -e "$dir"
	then
		local repository=$1
		local refspec=${2#+}
		local remoteref=${refspec#*:}
		local localrevname_presplit
		if test "$remoteref" = "$refspec"
		then
			localrevname_presplit=HEAD
		else
			localrevname_presplit=${refspec%%:*}
		fi
		case "$remoteref" in
		refs/*) :;;
		*) remoteref="refs/heads/$remoteref";;
		esac
		ensure_valid_ref_format "$remoteref"
		local localrev_presplit
		localrev_presplit=$(git rev-parse -q --verify "$localrevname_presplit^{commit}") ||
			die "'$localrevname_presplit' does not refer to a commit"
		debug

		echo "git push using: " "$repository" "$refspec"
		local localrev
		localrev=$(cmd_split "$localrev_presplit") || die
		git push "$repository" "$localrev:$remoteref"
	else
		die "'$dir' must already exist. Try 'git subtree add'."
	fi
}

main "$@"

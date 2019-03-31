#!/bin/sh
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
#    + cachedir (readonly)
#    + indent (mutable, kinda)

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
rejoin        merge the new branch back into HEAD
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

	set -eu

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
			--annotate|-b|-P|-m|--onto)
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
	arg_split_onto=
	arg_split_ignore_joins=
	arg_split_annotate=
	arg_addmerge_squash=
	arg_addmerge_message=
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
			arg_split_onto=$(git rev-parse -q --verify "$1^{commit}") ||
				die "'$1' does not refer to a commit"
			shift
			;;
		--no-onto)
			test -n "$allow_split" || die "The '$opt' flag does not make sense with 'git subtree $arg_command'."
			arg_split_onto=
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
	readonly arg_split_ignore_joins
	readonly arg_split_annotate
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
	debug

	"cmd_$arg_command" "$@"
}

# Usage: cache_setup
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
cache_setup () {
	assert test $# = 0
	if test "${cachedir:-}" = "$GIT_DIR/subtree-cache/$$"
	then
		return
	fi
	cachedir="$GIT_DIR/subtree-cache/$$" # global
	readonly cachedir
	rm -rf "$cachedir" ||
		die "Can't delete old cachedir: $cachedir"
	mkdir -p "$cachedir" ||
		die "Can't create new cachedir: $cachedir"
	mkdir -p "$cachedir/notree" ||
		die "Can't create new cachedir: $cachedir/notree"
	true > "$cachedir/subtree" ||
		die "Can't create new cachedir: $cachedir/subtree"
	debug "Using cachedir: $cachedir" >&2
}

# Usage: cache_get [REVS...]
cache_get () {
	assert test -n "$cachedir"
	local oldrev
	for oldrev in "$@"
	do
		if test -r "$cachedir/$oldrev"
		then
			cat "$cachedir/$oldrev"
		fi
	done
}

# Usage: ensure_parents [PARENTS...]
#
# Ensure that each commit in the list of 0 or more PARENTS is
# accounted for in the cache.
ensure_parents () {
	local indent=$(($indent + 1))

	# The list of parents must either (1) already have a cached
	# mapping, or (2) be cached as not containing the subtree
	# (i.e. the cache says "no mapping is possible").
	local parent
	for parent in "$@"
	do
		if ! test -r "$cachedir/$parent" && ! test -r "$cachedir/notree/$parent"
		then
			# Die.
			debug "Unexpected non-cached parent: $parent"
			process_split_commit "$parent" ""
		fi
	done
}

# Usage: set_notree REV
set_notree () {
	assert test $# = 1
	assert test -n "$cachedir"
	echo "1" > "$cachedir/notree/$1"
}

# Usage: cache_set_internal COMMIT SUBTREE_COMMIT
#
# See cache_set.
cache_set_internal () {
	assert test $# = 2
	assert test -n "$cachedir"
	local key="$1"
	local val="$2"
	debug "caching commit:$key = subtree_commit:$val"
	case "$key" in
	latest_old|latest_new)
		:
		;;
	*)
		if test -e "$cachedir/$key"
		then
			local oldval
			oldval=$(cat "$cachedir/$key")
			if test "$oldval" = "$val"
			then
				debug "already cached: commit:$key = subtree_commit:$val"
				return
			else
				die "caching commit:$key = subtree_commit:$val conflicts with existing subtree_commit:$oldval!"
			fi
		fi
		echo "$val" >>"$cachedir/subtree"
		;;
	esac
	echo "$val" >"$cachedir/$key"
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

	if test "$key" != "$val"
	then
		cache_set_internal "$key" "$val"
	else
		# If we've stumbled on to a true subtree-commit, go
		# ahead and mark its entire history as being able to
		# be used verbatim.
		local indent=$(($indent + 1))
		local rev
		git rev-list "$val" |
		while read -r rev
		do
			cache_set_internal "$rev" "$rev"
		done || exit $?
	fi
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

# Usage: try_remove_previous REV
#
# If a commit doesn't have a parent, this might not work.  But we only want
# to remove the parent from the rev-list, and since it doesn't exist, it won't
# be there anyway, so do nothing in that case.
try_remove_previous () {
	assert test $# = 1
	if rev_exists "$1^"
	then
		echo "^$1^"
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
	debug "Looking for latest squash ($dir)..."
	local indent=$(($indent + 1))

	local sq=
	local main=
	local sub=
	local a b junk
	git log --grep="^git-subtree-dir: $dir/*\$" \
		--no-show-signature --pretty=format:'START %H%n%s%n%n%b%nEND%n' "$@" |
	while read -r a b junk
	do
		debug "$a $b $junk"
		debug "{{$sq/$main/$sub}}"
		case "$a" in
		START)
			sq="$b"
			;;
		git-subtree-mainline:)
			main="$b"
			;;
		git-subtree-split:)
			sub="$(git rev-parse "$b^{commit}")" ||
			die "could not rev-parse split hash $b from commit $sq"
			;;
		END)
			if test -n "$sub"
			then
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
					sq=$(git rev-parse --verify "$sq^2") ||
						die
				fi
				debug "Squash found: $sq $sub"
				echo "$sq" "$sub"
				break
			fi
			sq=
			main=
			sub=
			;;
		esac
	done || exit $?
}

# Usage: find_existing_splits REV
find_existing_splits () {
	assert test $# = 1
	local rev="$1"
	debug "Looking for prior splits..."
	local indent=$(($indent + 1))

	if test -n "$arg_split_onto"
	then
		debug "cli --onto: $arg_split_onto"
		cache_set "$arg_split_onto" "$arg_split_onto"
		try_remove_previous "$arg_split_onto"
	fi

	local grep_format="^git-subtree-dir: $dir/*\$"
	if test -n "$arg_split_ignore_joins"
	then
		grep_format="^Add '$dir/' from commit '"
	fi

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
			sub="$(git rev-parse "$b^{commit}")" ||
			die "could not rev-parse split hash $b from commit $sq"
			;;
		END)
			if test -n "$sub"
			then
				if test -z "$main"
				then
					debug "prior --squash: $sq"
					debug "  git-subtree-split: '$sub'"
					cache_set "$sq" "$sub"
				else
					debug "prior --rejoin: $sq"
					debug "  git-subtree-mainline: '$main'"
					debug "  git-subtree-split:    '$sub'"
					cache_set "$main" "$sub"
					cache_set "$sub" "$sub"
					try_remove_previous "$main"
					try_remove_previous "$sub"
				fi
			fi
			sq=
			main=
			sub=
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

	local latest_old latest_new
	latest_old=$(cache_get latest_old) || exit $?
	latest_new=$(cache_get latest_new) || exit $?

	local commit_message
	if test -n "$arg_addmerge_message"
	then
		commit_message="$arg_addmerge_message"
	else
		commit_message="Add '$dir/' from commit '$latest_new'"
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
		git-subtree-mainline: $latest_old
		git-subtree-split: $latest_new
	EOF
}

# Usage: add_squashed_msg
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
add_squashed_msg () {
	assert test $# = 0

	local latest_new
	latest_new=$(cache_get latest_new) || exit $?

	if test -n "$arg_addmerge_message"
	then
		echo "$arg_addmerge_message"
	else
		echo "Merge commit '$latest_new' as '$dir'"
	fi
}

# Usage: rejoin_msg
#
# shellcheck disable=SC2120 # `test $# = 0` makes shellcheck think we take args
rejoin_msg () {
	assert test $# = 0

	local latest_old latest_new
	latest_old=$(cache_get latest_old) || exit $?
	latest_new=$(cache_get latest_new) || exit $?

	local commit_message
	if test -n "$arg_addmerge_message"
	then
		commit_message="$arg_addmerge_message"
	else
		commit_message="Split '$dir/' into commit '$latest_new'"
	fi
	cat <<-EOF
		$commit_message

		git-subtree-dir: $dir
		git-subtree-mainline: $latest_old
		git-subtree-split: $latest_new
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
	git rev-parse --verify "$commit^{tree}" || exit $?
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
		test "$type" = "commit" && continue  # ignore submodules
		echo "$tree"
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
		echo "$identical"
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

# Usage: process_split_commit REV PARENTS
process_split_commit () {
	assert test $# = 2
	local rev="$1"
	local parents="$2"

	if test "$indent" -gt 0
	then
		# processing commit without normal parent information;
		# fetch from repo
		parents=$(git rev-parse "$rev^@")
		extracount=$(($extracount + 1)) # in parent scope
	fi
	revcount=$(($revcount + 1)) # in parent scope

	progress "rev:$revcount/($revmax+$extracount) (created:$createcount)"

	debug "Processing commit: $rev"
	local indent=$(($indent + 1))

	cached=$(cache_get "$rev") || exit $?
	if test -n "$cached"
	then
		debug "cached: $cached"
		return
	fi

	tree=$(subtree_for_commit "$rev") || exit $?
	debug "dir tree: $tree"
	if test -z "$tree"
	then
		# This is either a mainline-commit without the
		# subtree, or a subtree-commit that has already been
		# split off.  We need to determine which.
		#
		# shellcheck disable=SC2046 # $(cat ...) is intentionally unquoted
		if ! git merge-base "$rev" -- $(cat "$cachedir/subtree") >/dev/null 2>&1
		then
			# It has no ancestor that is known to be a
			# subtree-commit; assume it's a
			# mainline-commit.
			set_notree "$rev"
			debug "notree"
			return
		else
			# It does have an ancesstor that is known to
			# be a subtree commit; assume it's a
			# subtree-commit.
			#
			# This could be a false-positive if the
			# subtree was deleted, however given that the
			# user asked us to split the subtree from this
			# rev, that seems unlikely.
			debug "subtree"
			cache_set "$rev" "$rev"
			cache_set latest_new "$newrev"
			return
		fi
	fi

	createcount=$((createcount + 1)) # in parent scope

	# shellcheck disable=SC2086
	debug parents: $parents
	# shellcheck disable=SC2086
	ensure_parents $parents
	# shellcheck disable=SC2086
	newparents=$(cache_get $parents) || exit $?
	# shellcheck disable=SC2086
	debug newparents: $newparents

	newrev=$(copy_or_skip "$rev" "$tree" "$newparents") || exit $?
	debug "newrev: $newrev"
	cache_set "$rev" "$newrev"
	cache_set latest_new "$newrev"
	cache_set latest_old "$rev"
}

# Usage: cmd_add REV
#    Or: cmd_add REPOSITORY REF
cmd_add () {

	ensure_clean

	cache_setup || exit $?

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
	rev=$(git rev-parse --verify "$1^{commit}") || exit $?

	debug "Adding $dir as '$rev'..."
	if test -z "$arg_split_rejoin"
	then
		# Only bother doing this if this is a genuine 'add',
		# not a synthetic 'add' from '--rejoin'.
		git read-tree --prefix="$dir" "$rev" || exit $?
	fi
	git checkout -- "$dir" || exit $?
	tree=$(git write-tree) || exit $?

	headrev=$(git rev-parse HEAD) || exit $?
	if test -n "$headrev" && test "$headrev" != "$rev"
	then
		headp="-p $headrev"
	else
		headp=
	fi

	cache_set latest_new "$rev"
	cache_set latest_old "$headrev"

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
	if test $# -eq 0
	then
		rev=$(git rev-parse HEAD)
	elif test $# -eq 1
	then
		rev=$(git rev-parse -q --verify "$1^{commit}") ||
			die "'$1' does not refer to a commit"
	else
		die "You must provide exactly one revision.  Got: '$*'"
	fi

	if test -n "$arg_split_rejoin"
	then
		ensure_clean
	fi

	debug "Splitting $dir..."
	cache_setup || exit $?

	local unrevs
	unrevs="$(find_existing_splits "$rev")" || exit $?
	debug
	debug "unrevs: {$unrevs}"
	debug

	# We can't restrict rev-list to only $dir here, because some of our
	# parents have the $dir contents the root, and those won't match.
	# (and rev-list --follow doesn't seem to solve this)
	local revmax
	# shellcheck disable=SC2086 # $unrevs is intentionally unquoted
	revmax=$(git rev-list --count "$rev" $unrevs) # global
	readonly revmax
	local revcount=0
	local createcount=0
	local extracount=0
	local lrev lparents
	# shellcheck disable=SC2086 # $unrevs is intentionally unquoted
	git rev-list --topo-order --reverse --parents "$rev" $unrevs |
	while read -r lrev lparents
	do
		process_split_commit "$lrev" "$lparents"
	done || exit $?

	local latest_new
	latest_new=$(cache_get latest_new) || exit $?
	if test -z "$latest_new"
	then
		die "No new revisions were found"
	fi

	if test -n "$arg_split_rejoin"
	then
		debug "Merging split branch into HEAD..."
		arg_addmerge_message="$(rejoin_msg)" || exit $?
		local latest_squash
		latest_squash=$(find_latest_squash "$rev") || exit $?
		if test -z "$latest_squash"
		then
			cmd_add "$latest_new" >&2 || exit $?
		else
			cmd_merge "$latest_new" >&2 || exit $?
		fi
	fi
	if test -n "$arg_split_branch"
	then
		local action
		if rev_exists "refs/heads/$arg_split_branch"
		then
			if ! git merge-base --is-ancestor "$arg_split_branch" "$latest_new"
			then
				die "Branch '$arg_split_branch' is not an ancestor of commit '$latest_new'."
			fi
			action='Updated'
		else
			action='Created'
		fi
		git update-ref -m 'subtree split' \
			"refs/heads/$arg_split_branch" "$latest_new" || exit $?
		say >&2 "$action branch '$arg_split_branch'"
	fi
	echo "$latest_new"
	exit 0
}

# Usage: cmd_merge REV
cmd_merge () {
	test $# -eq 1 ||
		die "You must provide exactly one revision.  Got: '$*'"
	local rev
	rev=$(git rev-parse -q --verify "$1^{commit}") ||
		die "'$1' does not refer to a commit"
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

		echo "git push using: " "$repository" "$refspec"
		local localrev
		localrev=$(cmd_split "$localrev_presplit") || die
		git push "$repository" "$localrev:$remoteref"
	else
		die "'$dir' must already exist. Try 'git subtree add'."
	fi
}

main "$@"

#!/bin/sh
#
# Copyright (c) 2012 Avery Pennaraum
# Copyright (c) 2015 Alexey Shumkin
#
test_description='Basic porcelain support for subtrees

This test verifies the basic operation of the add, pull, merge
and split subcommands of git subtree.
'

TEST_DIRECTORY=$(pwd)/../../../t
. "$TEST_DIRECTORY"/test-lib.sh

test_create_commit () (
	repo=$1 &&
	commit=$2 &&
	cd "$repo" &&
	mkdir -p "$(dirname "$commit")" \
	|| error "Could not create directory for commit"
	echo "$commit" >"$commit" &&
	git add "$commit" || error "Could not add commit"
	git commit -m "$commit" || error "Could not commit"
)

last_commit_subject () {
	git log --pretty=format:%s -1
}

#
# Tests for 'git subtree add'
#

test_expect_success 'no merge from non-existent subtree' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		test_must_fail git subtree merge --prefix="sub dir" FETCH_HEAD
	)
'

test_expect_success 'no pull from non-existent subtree' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		test_must_fail git subtree pull --prefix="sub dir" ./"sub proj" HEAD
	)
'

test_expect_success 'add subproj as subtree into sub dir/ with --prefix' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD &&
		test "$(last_commit_subject)" = "Add '\''sub dir/'\'' from commit '\''$(git rev-parse FETCH_HEAD)'\''"
	)
'

test_expect_success 'add subproj as subtree into sub dir/ with --prefix and --message' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" --message="Added subproject" FETCH_HEAD &&
		test "$(last_commit_subject)" = "Added subproject"
	)
'

test_expect_success 'add subproj as subtree into sub dir/ with --prefix as -P and --message as -m' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add -P "sub dir" -m "Added subproject" FETCH_HEAD &&
		test "$(last_commit_subject)" = "Added subproject"
	)
'

test_expect_success 'add subproj as subtree into sub dir/ with --squash and --prefix and --message' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" --message="Added subproject with squash" --squash FETCH_HEAD &&
		test "$(last_commit_subject)" = "Added subproject with squash"
	)
'

#
# Tests for 'git subtree merge'
#

test_expect_success 'merge new subproj history into sub dir/ with --prefix' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		test "$(last_commit_subject)" = "Merge commit '\''$(git rev-parse FETCH_HEAD)'\''"
	)
'

test_expect_success 'merge new subproj history into sub dir/ with --prefix and --message' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" --message="Merged changes from subproject" FETCH_HEAD &&
		test "$(last_commit_subject)" = "Merged changes from subproject"
	)
'

test_expect_success 'merge new subproj history into sub dir/ with --squash and --prefix and --message' '
	test_create_repo "$test_count/sub proj" &&
	test_create_repo "$test_count" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" --message="Merged changes from subproject using squash" --squash FETCH_HEAD &&
		test "$(last_commit_subject)" = "Merged changes from subproject using squash"
	)
'

test_expect_success 'merge the added subproj again, should do nothing' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD &&
		# this shouldn not actually do anything, since FETCH_HEAD
		# is already a parent
		result=$(git merge -s ours -m "merge -s -ours" FETCH_HEAD) &&
		test "${result}" = "Already up to date."
	)
'

test_expect_success 'merge new subproj history into subdir/ with a slash appended to the argument of --prefix' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/subproj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/subproj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./subproj HEAD &&
		git subtree add --prefix=subdir/ FETCH_HEAD
	) &&
	test_create_commit "$test_count/subproj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./subproj HEAD &&
		git subtree merge --prefix=subdir/ FETCH_HEAD &&
		test "$(last_commit_subject)" = "Merge commit '\''$(git rev-parse FETCH_HEAD)'\''"
	)
'

#
# Tests for 'git subtree split'
#

test_expect_success 'split requires option --prefix' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD &&
		echo "You must provide the --prefix option." > expected &&
		test_must_fail git subtree split > actual 2>&1 &&
		test_debug "printf '"expected: "'" &&
		test_debug "cat expected" &&
		test_debug "printf '"actual: "'" &&
		test_debug "cat actual" &&
		test_cmp expected actual
	)
'

test_expect_success 'split requires path given by option --prefix must exist' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD &&
		echo "'\''non-existent-directory'\'' does not exist; use '\''git subtree add'\''" > expected &&
		test_must_fail git subtree split --prefix=non-existent-directory > actual 2>&1 &&
		test_debug "printf '"expected: "'" &&
		test_debug "cat expected" &&
		test_debug "printf '"actual: "'" &&
		test_debug "cat actual" &&
		test_cmp expected actual
	)
'

test_expect_success 'split sub dir/ with --rejoin' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		split_hash=$(git subtree split --prefix="sub dir" --annotate="*") &&
		git subtree split --prefix="sub dir" --annotate="*" --rejoin &&
		test "$(last_commit_subject)" = "Split '\''sub dir/'\'' into commit '\''$split_hash'\''"
	)
'

test_expect_success 'split sub dir/ with --rejoin from scratch' '
	test_create_repo "$test_count" &&
	test_create_commit "$test_count" main1 &&
	(
		cd "$test_count" &&
		mkdir "sub dir" &&
		echo file >"sub dir"/file &&
		git add "sub dir/file" &&
		git commit -m"sub dir file" &&
		split_hash=$(git subtree split --prefix="sub dir" --rejoin) &&
		git subtree split --prefix="sub dir" --rejoin &&
		test "$(last_commit_subject)" = "Split '\''sub dir/'\'' into commit '\''$split_hash'\''"
	)
'

test_expect_success 'split sub dir/ with --rejoin and --message' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --message="Split & rejoin" --annotate="*" --rejoin &&
		test "$(last_commit_subject)" = "Split & rejoin"
	)
'

test_expect_success 'split "sub dir"/ with --branch' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		split_hash=$(git subtree split --prefix="sub dir" --annotate="*") &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br &&
		test "$(git rev-parse subproj-br)" = "$split_hash"
	)
'

test_expect_success 'check hash of split' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		split_hash=$(git subtree split --prefix="sub dir" --annotate="*") &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br &&
		test "$(git rev-parse subproj-br)" = "$split_hash" &&
		# Check hash of split
		new_hash=$(git rev-parse subproj-br^2) &&
		(
			cd ./"sub proj" &&
			subdir_hash=$(git rev-parse HEAD) &&
			test "$new_hash" = "$subdir_hash"
		)
	)
'

test_expect_success 'split "sub dir"/ with --branch for an existing branch' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git branch subproj-br FETCH_HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		split_hash=$(git subtree split --prefix="sub dir" --annotate="*") &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br &&
		test "$(git rev-parse subproj-br)" = "$split_hash"
	)
'

test_expect_success 'split "sub dir"/ with --branch for an incompatible branch' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git branch init HEAD &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		test_must_fail git subtree split --prefix="sub dir" --branch init
	)
'

#
# Validity checking
#

test_expect_success 'make sure exactly the right set of files ends up in the subproj' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD &&

		test_write_lines main-sub1 main-sub2 main-sub3 main-sub4 \
			sub1 sub2 sub3 sub4 >expect &&
		git ls-files >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'make sure the subproj *only* contains commits that affect the "sub dir"' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD &&

		test_write_lines main-sub1 main-sub2 main-sub3 main-sub4 \
			sub1 sub2 sub3 sub4 >expect &&
		git log --name-only --pretty=format:"" >log &&
		sort <log | sed "/^\$/ d" >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'make sure exactly the right set of files ends up in the mainline' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	(
		cd "$test_count" &&
		git subtree pull --prefix="sub dir" ./"sub proj" HEAD &&

		test_write_lines main1 main2 >chkm &&
		test_write_lines main-sub1 main-sub2 main-sub3 main-sub4 >chkms &&
		sed "s,^,sub dir/," chkms >chkms_sub &&
		test_write_lines sub1 sub2 sub3 sub4 >chks &&
		sed "s,^,sub dir/," chks >chks_sub &&

		cat chkm chkms_sub chks_sub >expect &&
		git ls-files >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'make sure each filename changed exactly once in the entire history' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git config log.date relative &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	(
		cd "$test_count" &&
		git subtree pull --prefix="sub dir" ./"sub proj" HEAD &&

		test_write_lines main1 main2 >chkm &&
		test_write_lines sub1 sub2 sub3 sub4 >chks &&
		test_write_lines main-sub1 main-sub2 main-sub3 main-sub4 >chkms &&
		sed "s,^,sub dir/," chkms >chkms_sub &&

		# main-sub?? and /"sub dir"/main-sub?? both change, because those are the
		# changes that were split into their own history.  And "sub dir"/sub?? never
		# change, since they were *only* changed in the subtree branch.
		git log --name-only --pretty=format:"" >log &&
		sort <log >sorted-log &&
		sed "/^$/ d" sorted-log >actual &&

		cat chkms chkm chks chkms_sub >expect-unsorted &&
		sort expect-unsorted >expect &&
		test_cmp expect actual
	)
'

test_expect_success 'make sure the --rejoin commits never make it into subproj' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	(
		cd "$test_count" &&
		git subtree pull --prefix="sub dir" ./"sub proj" HEAD &&
		test "$(git log --pretty=format:"%s" HEAD^2 | grep -i split)" = ""
	)
'

test_expect_success 'make sure no "git subtree" tagged commits make it into subproj' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count/sub proj" sub3 &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		 git merge FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub4 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --annotate="*" --branch subproj-br --rejoin
	) &&
	(
		cd "$test_count/sub proj" &&
		git fetch .. subproj-br &&
		git merge FETCH_HEAD
	) &&
	(
		cd "$test_count" &&
		git subtree pull --prefix="sub dir" ./"sub proj" HEAD &&

		# They are meaningless to subproj since one side of the merge refers to the mainline
		test "$(git log --pretty=format:"%s%n%b" HEAD^2 | grep "git-subtree.*:")" = ""
	)
'

#
# A new set of tests
#

test_expect_success 'make sure "git subtree split" find the correct parent' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git branch subproj-ref FETCH_HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --branch subproj-br &&

		# at this point, the new commit parent should be subproj-ref, if it is
		# not, something went wrong (the "newparent" of "HEAD~" commit should
		# have been sub2, but it was not, because its cache was not set to
		# itself)
		test "$(git log --pretty=format:%P -1 subproj-br)" = "$(git rev-parse subproj-ref)"
	)
'

test_expect_success 'split a new subtree without --onto option' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --branch subproj-br
	) &&
	mkdir "$test_count"/"sub dir2" &&
	test_create_commit "$test_count" "sub dir2"/main-sub2 &&
	(
		cd "$test_count" &&

		# also test that we still can split out an entirely new subtree
		# if the parent of the first commit in the tree is not empty,
		# then the new subtree has accidentally been attached to something
		git subtree split --prefix="sub dir2" --branch subproj2-br &&
		test "$(git log --pretty=format:%P -1 subproj2-br)" = ""
	)
'

test_expect_success 'verify one file change per commit' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git branch sub1 FETCH_HEAD &&
		git subtree add --prefix="sub dir" sub1
	) &&
	test_create_commit "$test_count/sub proj" sub2 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir" --branch subproj-br
	) &&
	mkdir "$test_count"/"sub dir2" &&
	test_create_commit "$test_count" "sub dir2"/main-sub2 &&
	(
		cd "$test_count" &&
		git subtree split --prefix="sub dir2" --branch subproj2-br &&

		git log --format="%H" > commit-list &&
		while read commit
		do
			git log -n1 --format="" --name-only "$commit" >file-list &&
			test_line_count -le 1 file-list || return 1
		done <commit-list
	)
'

test_expect_success 'push split to subproj' '
	test_create_repo "$test_count" &&
	test_create_repo "$test_count/sub proj" &&
	test_create_commit "$test_count" main1 &&
	test_create_commit "$test_count/sub proj" sub1 &&
	(
		cd "$test_count" &&
		git fetch ./"sub proj" HEAD &&
		git subtree add --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub1 &&
	test_create_commit "$test_count" main2 &&
	test_create_commit "$test_count/sub proj" sub2 &&
	test_create_commit "$test_count" "sub dir"/main-sub2 &&
	(
		cd $test_count/"sub proj" &&
		git branch sub-branch-1 &&
		cd .. &&
		git fetch ./"sub proj" HEAD &&
		git subtree merge --prefix="sub dir" FETCH_HEAD
	) &&
	test_create_commit "$test_count" "sub dir"/main-sub3 &&
	(
		cd "$test_count" &&
		git subtree push ./"sub proj" --prefix "sub dir" sub-branch-1 &&
		cd ./"sub proj" &&
		git checkout sub-branch-1 &&
		test "$(last_commit_subject)" = "sub dir/main-sub3"
	)
'

#
# This test covers 2 cases in subtree split copy_or_skip code
# 1) Merges where one parent is a superset of the changes of the other
#    parent regarding changes to the subtree, in this case the merge
#    commit should be copied
# 2) Merges where only one parent operate on the subtree, and the merge
#    commit should be skipped
#
# (1) is checked by ensuring subtree_tip is a descendent of subtree_branch
# (2) should have a check added (not_a_subtree_change shouldn't be present
#     on the produced subtree)
#
# Other related cases which are not tested (or currently handled correctly)
# - Case (1) where there are more than 2 parents, it will sometimes correctly copy
#   the merge, and sometimes not
# - Merge commit where both parents have same tree as the merge, currently
#   will always be skipped, even if they reached that state via different
#   set of commits.
#

test_expect_success 'subtree descendant check' '
	test_create_repo "$test_count" &&
	defaultBranch=$(sed "s,ref: refs/heads/,," "$test_count/.git/HEAD") &&
	test_create_commit "$test_count" folder_subtree/a &&
	(
		cd "$test_count" &&
		git branch branch
	) &&
	test_create_commit "$test_count" folder_subtree/0 &&
	test_create_commit "$test_count" folder_subtree/b &&
	cherry=$(cd "$test_count"; git rev-parse HEAD) &&
	(
		cd "$test_count" &&
		git checkout branch
	) &&
	test_create_commit "$test_count" commit_on_branch &&
	(
		cd "$test_count" &&
		git cherry-pick $cherry &&
		git checkout $defaultBranch &&
		git merge -m "merge should be kept on subtree" branch &&
		git branch no_subtree_work_branch
	) &&
	test_create_commit "$test_count" folder_subtree/d &&
	(
		cd "$test_count" &&
		git checkout no_subtree_work_branch
	) &&
	test_create_commit "$test_count" not_a_subtree_change &&
	(
		cd "$test_count" &&
		git checkout $defaultBranch &&
		git merge -m "merge should be skipped on subtree" no_subtree_work_branch &&

		git subtree split --prefix folder_subtree/ --branch subtree_tip $defaultBranch &&
		git subtree split --prefix folder_subtree/ --branch subtree_branch branch &&
		test $(git rev-list --count subtree_tip..subtree_branch) = 0
	)
'

test_done

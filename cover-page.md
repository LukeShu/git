Test-suite code quality 

   subtree: t7900: Take advantage of test-lib.sh's test_count
    subtree: t7900: Use consistent formatting
    subtree: t7900: Use test_create_repo instead of subtree_test_create_repo
    subtree: t7900: Delete some dead code
    subtree: t7900: Fix and simplify 'verify one file change per commit'

Implementation code quality

   subtree: Avoid having loose code outside of a function
    subtree: Have more consistent error propagation
    subtree: Drop support for git < 1.7
    subtree: Drop slow function for `git merge-base --is-ancestor`
    subtree: Use git-sh-setup's `say`
    subtree: Use more explicit variable names for cmdline flags
    subtree: Use $* instead of $@ as appropriate
    subtree: Variables inside of $(( )) don't need a $
    subtree: Give `$(git --exec-path)` precedence over `$PATH`, like other commands
    subtree: Use "^{commit}" instead of "^0"
    subtree: Parse revs in individual cmd_ functions; avoid globals
    subtree: Remove duplicate check
    subtree: Add comments and sanity checks

UX improvements

   subtree: Don't have -d[ebug] and the progress output stomp on eachother
    subtree: Have $indent actually affect indentation
    subtree: Indicate in the '-h' text that the <commit> for split is optional
    subtree: Allow 'split' args to be passed to 'push'
    subtree: push: Allow specifying the local rev instead of HEAD
    subtree: Allow --squash to be used with --rejoin

Pending

    debug noise
    subtree: Be stricter about validating flags
    wip strict
    history search
    better --onto, history pruning
    fixup
    cache/onto fix
    indent
    progres
    stuff

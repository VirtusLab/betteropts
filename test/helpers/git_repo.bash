# Shared by tests exercising type=git-commitish (features/05-type-git-commitish.md).

# Initializes a throwaway git repo in $BATS_TEST_TMPDIR and cds into it: two
# commits on the default branch, a second branch, and a tag - enough to
# exercise a SHA, an abbreviated SHA, HEAD~1, a branch name, and a tag name.
# Sets $GIT_REPO_HEAD to the tip commit's full SHA.
setup_git_repo() {
  cd "$BATS_TEST_TMPDIR" || exit 1
  git init -q .
  git config user.email "test@example.com"
  git config user.name "Test"
  echo one > file.txt
  git add file.txt
  git commit -q -m "first commit"
  echo two >> file.txt
  git add file.txt
  git commit -q -m "second commit"
  git branch feature-branch
  git tag v1.0
  # shellcheck disable=SC2034 # used by callers after sourcing this helper
  GIT_REPO_HEAD="$(git rev-parse HEAD)"
}

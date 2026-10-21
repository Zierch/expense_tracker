# AGENTS.md

Conventions for anyone — human or agent — changing this repository.

## Delete the branch after a pull request merges cleanly

When a pull request merges without conflicts and the head branch holds no work
that did not reach `main`, delete the head branch. Both copies:

```sh
git switch main
git pull --ff-only
git branch -d <branch>
git push origin --delete <branch>
```

The merge commit already carries those commits into `main`, so the branch is a
second, stale name for the same history. Left behind, it makes the branch list
unreadable and hides which branches are actually live.

Verify before deleting rather than assuming the merge landed:

```sh
gh pr view <n> --json state,mergeStateStatus   # state must be MERGED
git fetch origin --prune
git log --oneline origin/main..origin/<branch> # must print nothing
```

`git log` printing nothing is the check that matters: it means every commit on the
branch is an ancestor of `main`. Use `git branch -d`, never `-D` — `-d` refuses to
delete a branch whose work is not merged, which is the safety net for the case
where the check above was skipped.

Do not delete the branch when any of these hold:

- the pull request was closed without merging — that work exists nowhere else;
- the merge did not complete cleanly (conflicts, a partial merge, `main` was not
  updated by it);
- commits were pushed to the head branch after the merge — those are the new
  changes that never reached `main`.

Never delete `main`.

Deleting a branch is a `delete` event, not a `push`, so it does not run the
workflow in `.github/workflows/ci.yml`. Nothing to wait for.
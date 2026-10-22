# AGENTS.md

Conventions for anyone — human or agent — changing this repository.

## Version numbers

`pubspec.yaml`'s `version:` is `x.y.z+n`, bumped by hand at release time, and the
tag is `v` plus that same `x.y.z`.

**Default to the last number.** `1.4.0` → `1.4.1`. A fix, a rename, a docs-only
release, a dependency pin, a small behaviour tweak — anything a user would not
call a new feature — moves the last number and nothing else. Most releases are
this one, so `x.y.0` is the odd case, not the rule.

The middle number is for a release that genuinely adds something: a new screen, a
new capability, a change a user could point at and call new.

Whatever moves, `+n` always goes up by one: Android refuses to install a build
whose `versionCode` is not greater than the one already on the phone.

Releases are published by pushing the version tag: `.github/workflows/release.yml`
builds, signs and attaches the APK, using the notes committed at
`docs/releases/v<version>.md`. Do not move or delete a published tag — phones
may already have read it — fix forward with the next patch instead.

That workflow's one fragile step is `Install host SQLite`, which talks to a
package mirror rather than to GitHub: it has hung once for 21 minutes while the
same step took 5 seconds earlier the same day. A run parked on that step is a
stuck mirror, not a slow build — cancel it, re-run it, and if it hangs twice
build the release locally and attach the APK by hand
(`README.md` → *Continuous integration* and *Publishing a release*).

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
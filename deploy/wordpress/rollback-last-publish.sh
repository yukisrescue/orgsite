#!/usr/bin/env bash
# Roll back the exported site by one publish, or restore site/ from a SHA.
#
# Host usage (node2):
#   ./rollback-last-publish.sh              # one publish older
#   ./rollback-last-publish.sh <commit>     # exact site/ state at commit
#
# The host wrapper streams this same script into yukis-publisher.  Keeping the
# git, deploy, and push steps in one container avoids credential and path drift.
set -euo pipefail

BRANCH="${BRANCH:-main}"
CONTAINER="${PUBLISHER_CONTAINER:-yukis-publisher}"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ "$#" -gt 1 ]; then
  die "usage: $0 [commit-sha]"
fi

# Tests can point directly at a disposable repository. Production uses the
# container path below; ROLLBACK_REPO_DIR is intentionally not set there.
if [ -n "${ROLLBACK_REPO_DIR:-}" ]; then
  REPO_DIR="$ROLLBACK_REPO_DIR"
elif [ "${ROLLBACK_IN_CONTAINER:-0}" != "1" ]; then
  command -v docker >/dev/null 2>&1 || die "docker is required on the host"
  running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" \
    || die "publisher container '$CONTAINER' does not exist"
  started_by_us=0
  if [ "$running" != "true" ]; then
    echo "publisher: starting $CONTAINER for rollback"
    docker start "$CONTAINER" >/dev/null || die "could not start $CONTAINER"
    started_by_us=1
  fi
  cleanup() {
    if [ "$started_by_us" -eq 1 ]; then
      echo "publisher: restoring $CONTAINER to stopped state"
      docker stop "$CONTAINER" >/dev/null || true
    fi
  }
  trap cleanup EXIT

  # The script is not required to be mounted into the container. This matters
  # when a source checkout is newer than the copy currently deployed on node2.
  if docker exec -i "$CONTAINER" env ROLLBACK_IN_CONTAINER=1 \
      bash -s -- "$@" < "$0"; then
    exit 0
  else
    rc=$?
    exit "$rc"
  fi
else
  REPO_DIR="${REPO_DIR:?set REPO_DIR}"
fi

git_at() { git -C "$REPO_DIR" "$@"; }

git_at rev-parse --git-dir >/dev/null 2>&1 \
  || die "$REPO_DIR is not a usable git repository"

branch="$(git_at symbolic-ref --short -q HEAD || true)"
[ "$branch" = "$BRANCH" ] \
  || die "repository must be on $BRANCH (currently ${branch:-detached})"

status="$(git_at status --porcelain 2>&1)" \
  || die "git status failed; refusing to guess repository state"
[ -z "$status" ] \
  || die "repository is not clean; commit or stash changes before rolling back"

target=""
commit_message=""
commit_body=""

if [ "$#" -eq 1 ]; then
  target="$(git_at rev-parse --verify "$1^{commit}" 2>/dev/null)" \
    || die "'$1' is not a valid commit SHA"
  git_at cat-file -e "$target:site/index.html" 2>/dev/null \
    || die "commit $target does not contain site/index.html"
  commit_message="rollback: restore site from $target"
  commit_body="Restored site/ exactly as it exists at $target."
else
  mapfile -t publishes < <(git_at log --format='%H' \
    --grep='^publish: static export ' -- site/)
  [ "${#publishes[@]}" -gt 0 ] \
    || die "no publish commits were found in the current history"

  # A manual `git revert` says which publish it undid. Our own rollback commit
  # says the same thing. That commit is the cursor; choose the next older
  # publish so repeated invocations walk backward instead of repeating a step.
  cursor=""
  # Ignore ordinary commits (for example a docs change) after a rollback, but
  # stop at a newer publish: that publish starts a new rollback walk.
  while IFS= read -r history_commit; do
    history_subject="$(git_at log -1 --format='%s' "$history_commit")"
    history_body="$(git_at log -1 --format='%B' "$history_commit")"
    if [[ "$history_body" =~ This\ reverts\ commit\ ([0-9a-fA-F]{7,40})\. ]]; then
      cursor="$(git_at rev-parse --verify "${BASH_REMATCH[1]}^{commit}")"
      break
    elif [[ "$history_subject" =~ ^rollback:\ restore\ site\ before\ ([0-9a-fA-F]{40})$ ]]; then
      cursor="${BASH_REMATCH[1]}"
      break
    elif [[ "$history_subject" =~ ^rollback:\ restore\ site\ from\ ([0-9a-fA-F]{40})$ ]]; then
      explicit_target="${BASH_REMATCH[1]}"
      # After an explicit jump, resume from the newest publish containing that
      # target as an ancestor, then move to the publish before it.
      for publish in "${publishes[@]}"; do
        if git_at merge-base --is-ancestor "$explicit_target" "$publish"; then
          cursor="$publish"
          break 2
        fi
      done
    elif [[ "$history_subject" == publish:\ static\ export\ * ]]; then
      break
    fi
  done < <(git_at log --format='%H')

  start=0
  if [ -n "$cursor" ]; then
    found=0
    for i in "${!publishes[@]}"; do
      if [ "${publishes[$i]}" = "$cursor" ]; then
        start=$((i + 1))
        found=1
        break
      fi
    done
    [ "$found" -eq 1 ] \
      || die "rollback cursor $cursor is not a publish commit in this history"
  fi
  [ "$start" -lt "${#publishes[@]}" ] \
    || die "no earlier publish commit is available"

  source_publish="${publishes[$start]}"
  target="$(git_at rev-parse --verify "${source_publish}^^{commit}")"
  git_at cat-file -e "$target:site/index.html" 2>/dev/null \
    || die "the previous publish parent $target does not contain site/index.html"
  commit_message="rollback: restore site before $source_publish"
  commit_body="Restored site/ from the parent of publish commit $source_publish."
  echo "rollback: $source_publish -> $target"
fi

if git_at diff --quiet HEAD "$target" -- site/; then
  echo "rollback: site/ already matches target $target; nothing to do"
  exit 0
fi

git_at restore --source "$target" -- site/
git_at add -A site/
git_at -c user.email="wordpress@yukisrescue.org" \
  -c user.name="Yuki's Rescue WordPress" \
  commit -q -m "$commit_message" -m "$commit_body"
rollback_commit="$(git_at rev-parse HEAD)"
echo "rollback: committed $rollback_commit"

if [ "${SKIP_DEPLOY:-0}" = "1" ]; then
  echo "rollback: deploy skipped"
else
  REPO_DIR="$REPO_DIR" /deploy.sh
fi

if [ "${SKIP_PUSH:-0}" = "1" ]; then
  echo "rollback: push skipped"
else
  if git_at push origin "$BRANCH"; then
    echo "rollback: pushed $rollback_commit"
  else
    die "rollback committed and deployed locally, but push to origin/$BRANCH failed"
  fi
fi

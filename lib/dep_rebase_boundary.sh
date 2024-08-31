#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2024 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Determines rebase ref. commit, and identifies one or more push remotes.
#
# - The rebase ref. is the youngest published commit, i.e., we can rebase
#   commits since this ref. and not worry about rewriting public history.
# - In the most basic use case where there's a single remote, the rebase
#   ref. is the remote HEAD.
#   - If you have a local 'release' (or 'private') branch, and the remote
#     branch REMOTE_BRANCH_RELEASE exists (e.g., 'publish/release'), sets
#       sort_from_commit='publish/release'
#   - For a feature branch (any branch not named 'release' or 'private'),
#     uses the remote name from the tracking branch, or from the --remote
#     CLI arg, paired with the feature branch name, e.g.,
#       sort_from_commit='<remote>/<branch>'
# - For a 'private' branch with no remote, uses the pw/private/in tag if
#   set, which is used by the put-wise-apply command and marks the latest
#   commit from the patches archive (which lets you move changes between
#   hosts using an encrypted patch archive, useful when you cannot use SSH
#   to git-fetch and still you want your data E2E encrypted between hosts).
# - May also baulk if a version or other tag is identified amongst the
#   rebase commits.
#
# - Also used by put-wise-push to suss other remote and branch vars.

# SORRY:
# - I don't generally like to "abuse" `local` like this. It seems
#   like a weird side-effect to have a fcn. set its caller's vars.
#   - But this is shell script, and passing data is not always so
#     simple or elegant.
#
# REFER:
# - This fcn. sets the following vars (its "return" values):
#     local_release=""
#     remote_release=""
#     remote_liminal=""
#     remote_protected=""
#     remote_current=""
#     remote_name=""
#     branch_name=""
#     sort_from_commit=""
# - Other side effects:
#   - Calls `git fetch` as appropriate to ensure remote branch
#     ref is accurate/up to date.
#   - Fails if bad state detected (e.g., diverged branches), or if
#     the rebase boundary (sort_from_commit) cannot be identified or
#     verified.
#
# BWARE:
# - This fcn. does not verify sort_from_commit is reachable from HEAD.
#   - See resort_and_sign_commits_before_push, which will `exit 1` if
#     sort_from_commit diverges,

put_wise_identify_rebase_boundary_and_remotes () {
  local action_desc="$1"

  # Caller vars set below:
  branch_name="$(git_branch_name)"
  local_release=""
  remote_release=""
  remote_liminal=""
  remote_protected=""
  remote_current=""
  remote_name=""
  sort_from_commit=""

  local force_liminal=false

  local sortless_msg=""

  local applied_tag="$(format_pw_tag_applied "${branch_name}")"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    || [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    local_release="${LOCAL_BRANCH_RELEASE}"
    remote_release="${REMOTE_BRANCH_RELEASE}"
    remote_liminal="${REMOTE_BRANCH_LIMINAL}"
    remote_protected="${REMOTE_BRANCH_SCOPING}"

    # The pw/in tag signifies the final patch from the latest --apply command.
    # It's the remote's HEAD, essentially (minus PRIVATE commits). This is the
    # fallback sort-from, in case there's no remote branch or local 'release'
    # branch. Note that this will move PRIVATE commits toward HEAD, but it'll
    # leave behind PROTECTED commits that may precede pw/work. (The pw/work tag
    # is the merge-base from the latest --apply command. It's what the patches
    # were based from, and it signifies what this host pushed before that the
    # remote added work to. I.e., when this host pushed pw/work, it had just
    # resorted, and PROTECTED commits were bubbled toward pw/work. So if we
    # wanted to move those commits forward now, we'd have to set sort-from to a
    # commit preceding pw/work. Fortunately, we can use the 'release' branch,
    # which precedes these PROTECTED commits, as the sort-from base. Using this
    # tag is just a fallback, but note that it means we won't move earlier
    # PROTECTED commits forward. Which we can say is a feature of not having a
    # 'release' branch.
    if git_tag_exists "${applied_tag}"; then
      sort_from_commit="${applied_tag}"
    fi

    # User can opt-into 'liminal' usage, or if remote branch exists,
    # then it's automatic. (User has to manually delete that branch
    # if you want to disable 'liminal' behavior.)
    if ${PW_OPTION_USE_LIMINAL:-false} || git_remote_branch_exists "${remote_liminal}"; then
      force_liminal=true
    else
      remote_liminal=""
    fi

    # Unless the 'pw/private/in' tag is set as the sort_from_commit default
    # (see above), use the protected remote (e.g., 'entrust/scoping') as the
    # default starting point for the sort-and-sign rebase (sort_from_commit).
    # - We'll pick a different starting point below if there's a remote
    #   release branch (e.g., 'publish/release') or if there's a local
    #   release branch (e.g., 'release'), which is the "normal" use case:
    #   - UCASE: Keep scoped (PROTECTED/PRIVATE) commits *ahead* of the
    #     'release' branches (so that you never publish scoped commits).
    #     - This is actually a core concept in put-wise: locally you have
    #       scoped commits that you never publish to the release remote.
    #       - PRIVATE commits are never pushed/pulled by put-wise (though
    #         you might sync them between personal hosts using SSH remotes
    #         and git-fetch).
    #       - PROTECTED commits are only shared via --archive or via
    #         --push to a protected remote (e.g., a private GH repo).
    # - Here we use the protected remote ('entrust/scoping') as the
    #   default in case there's no 'release' branch (local or remote).
    # - Note if this is the only rebase boundary identified, the scoped
    #   sort will not include PROTECTED commits that were previously
    #   pushed to the protected remote. Which is fine. User can manually
    #   sort-by-scope to bubble them up, if they care (and note that the
    #   protected remote does not guarantee linear history, and user may
    #   need to force-push if they bubble up previously pushed PROTECTED
    #   commits).
    if git_remote_branch_exists "${remote_protected}"; then
      if [ -z "${sort_from_commit}" ]; then
        sort_from_commit="${remote_protected}"
      fi

      # Always fetch the remote, so that our ref is current,
      # because this function also does a lot of state validating.
      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      echo_announce "Fetch from ‘${SCOPING_REMOTE_NAME}’"

      git fetch "${SCOPING_REMOTE_NAME}"
    else
      remote_protected=""
    fi

    # Prefer sorting from local or remote 'release' branch. This is easier
    # than walking from pw/work to see when scoping ends, and sorting from
    # there.
    if git_remote_branch_exists "${remote_release}"; then
      sort_from_commit="${remote_release}"

      echo_announce "Fetch from ‘${RELEASE_REMOTE_NAME}’"

      # So that merge-base is accurate.
      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      git fetch "${RELEASE_REMOTE_NAME}"
    else
      remote_release=""
    fi

    if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
      if git_branch_exists "${local_release}"; then
        sort_from_commit="${local_release}"
      else
        local_release=""
      fi
    elif [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ]; then
      if git_branch_exists "${LOCAL_BRANCH_PRIVATE}"; then
        warn "ALERT: Working from branch '${LOCAL_BRANCH_RELEASE}'," \
          "but '${LOCAL_BRANCH_PRIVATE}' branch also exists"
      fi
    fi

    # else, if sort_from_commit unset, will die after return from if-block.

    if [ -n "${remote_release}" ] && [ -n "${local_release}" ]; then
      # Verify 'release/release' is at or behind 'release'.
      local divergent_ok=false

      must_confirm_commit_at_or_behind_commit "${remote_release}" "${local_release}" \
        ${divergent_ok} "remote-release" "local-release"

      if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
        # Rebase starting from 'release', which is guaranteed at or further
        # along than 'publish/release'.
        sort_from_commit="${local_release}"
      fi
    fi

    # When liminal enabled, we never force-push to 'release'.
    if ${PW_OPTION_FORCE_PUSH:-false} && ${force_liminal}; then
      local_release=""
      remote_release=""
    fi

    # NOTE: If resorting since 'release' or 'publish/release', it means
    #       you will need to push --force 'entrust/scoping', and then
    #       on the @business device, you need to rebase on pull. Just
    #       how it works because you're managing so many unshareable
    #       forks.

  # fi: very long [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]

  else
    # ${branch_name} not 'release' or 'private'.
    # - Note that push.default defaults to 'simple', which pushes to upstream
    #   tracking branch when pushing to that remote, otherwise works like
    #   push.default 'current', which uses same name for pushing.
    #   - For feature branches, I like to track the trunk, so git-pull
    #     rebases appropriately. But I like push.default 'current', so
    #     that push uses the same feature branch name that I use locally.
    # - The following effectively mimics 'current'.
    local tracking_branch
    tracking_branch="$(git_tracking_branch)" \
      || true

    remote_name="${PW_OPTION_REMOTE}"

    if [ -z "${remote_name}" ] && [ -n "${tracking_branch}" ]; then
      remote_name="$(git_upstream_parse_remote_name "${tracking_branch}")"
    fi

    # Note we don't use PW_OPTION_BRANCH here, but the current branch.
    remote_current="${remote_name}/${branch_name}"

    if git_remote_exists "${remote_name}"; then
      echo_announce "Fetch from ‘${remote_name}’"

      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      git fetch "${remote_name}"

      if ! ${PW_OPTION_FORCE_PUSH:-false} && git_remote_branch_exists "${remote_current}"; then
        sort_from_commit="${remote_current}"
      fi
    fi

    if [ -z "${sort_from_commit}" ] && [ -n "${tracking_branch}" ]; then
      sort_from_commit="${tracking_branch}"
    fi
  fi

  if ${PUT_WISE_SKIP_REBASE:-false}; then
    sort_from_commit=""
  else
    if [ -n "${PW_OPTION_STARTING_REF}" ]; then
      >&2 echo "ALERT: Overriding rebase ref. with command line value:"
      >&2 echo "- Default ref: ${sort_from_commit}"
      >&2 echo "- Command arg: ${PW_OPTION_STARTING_REF}"

      sort_from_commit="${PW_OPTION_STARTING_REF}"
    fi

    # Because we rebase to reorder scoping commits, we need to identify
    # a starting ref. Without a starting ref, it gets complicated (do
    # we resort everything? Do we find the first PROTECTED or PRIVATE
    # commit and rebase from there?). It's easier to tell the user to
    # make the first push.
    if ! verify_rebase_boundary_exists "${sort_from_commit}"; then
      ${PW_OPTION_FAIL_ELEVENSES} && exit ${PW_ELEVENSES}

      alert_cannot_identify_rebase_boundary \
        "${branch_name}" \
        "${remote_name}" \
        "${sort_from_commit}"

      exit 1
    fi

    debug_alert_if_ref_tags_at_or_behind_sort_from_commit \
      "${branch_name}" "${sort_from_commit}" "${applied_tag}"
  fi
}

# ***

# Overzealous UX reporting if diverging from tags, not sure why I care
# to alert user.

debug_alert_if_ref_tags_at_or_behind_sort_from_commit () {
  local branch_name="$1"
  local sort_from_commit="$2"
  local applied_tag="$3"

  local work_tag="$(format_pw_tag_starting "${branch_name}")"

  for tag_name in \
    "${applied_tag}" \
    "$(format_pw_tag_archived "${branch_name}")" \
    "${work_tag}" \
  ; do
    if $(must_confirm_shares_history_with_head "${tag_name}" > /dev/null 2>&1); then
      local divergent_ok=false

      if ! $( \
        must_confirm_commit_at_or_behind_commit \
          "${tag_name}" "${sort_from_commit}" ${divergent_ok} \
          "tag-name" "sort-from" \
            > /dev/null 2>&1 \
      ); then
        >&2 debug "FYI: '${tag_name}' tag moving to headless sequence" \
          "until reused by future put-wise"
      fi
    fi
  done
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

verify_rebase_boundary_exists () {
  local sort_from_commit="$1"

  if [ -z "${sort_from_commit}" ]; then

    return 1
  fi

  git_commit_object_name ${sort_from_commit} > /dev/null
}

# ***

alert_cannot_identify_rebase_boundary () {
  local branch_name="$1"
  local tracking_remote_name="$2"
  local sort_from_commit="$3"

  local is_gpw_itself=false
  if [ "$(basename -- "$0")" = "git-put-wise" ]; then
    is_gpw_itself=true
  fi

  >&2 echo "ERROR: Could not identify the rebase boundary"
  >&2 echo
  >&2 echo "- A rebase boundary must be identified as the"
  >&2 echo "  starting point for the sort and sign rebase"
  >&2 echo
  >&2 echo "POSSIBLE SOLUTIONS:"
  >&2 echo
  >&2 echo "- OPTION 1: If you want to specify the rebase boundary"
  >&2 echo "  manually, use the command line option:"
  >&2 echo "    -S|--starting-ref <ref>"
  >&2 echo "  or use its environ:"
  >&2 echo "    PW_OPTION_STARTING_REF=\"<ref>\""
  >&2 echo
  >&2 echo "- OPTION 2: If you want to skip the sort and sign rebase"
  >&2 echo "  altogether, set the environ:"
  >&2 echo "    PUT_WISE_SKIP_REBASE=true"
  >&2 echo
  >&2 echo "- OPTION 3: Create one of the missing references:"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ] \
    || [ "${branch_name}" = "${LOCAL_BRANCH_RELEASE}" ] \
  ; then
    # NOTED: Not mentioning REMOTE_BRANCH_LIMINAL.
    >&2 echo "- The local branch '${branch_name}' pushes to"
    >&2 echo "  the remote branch '${REMOTE_BRANCH_RELEASE}', and also"
    >&2 echo "  the remote branch '${REMOTE_BRANCH_SCOPING}' if it exists,"
    >&2 echo "  but neither of those remote branches exist. So either:"
    >&2 echo "    \`git push ${RELEASE_REMOTE_NAME} <SHA>:refs/heads/${RELEASE_REMOTE_BRANCH}\`"
    >&2 echo "  or:"
    >&2 echo "    \`git push ${SCOPING_REMOTE_NAME} <SHA>:refs/heads/${SCOPING_REMOTE_BRANCH}\`"
    if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
      >&2 echo "- The local branch '${LOCAL_BRANCH_PRIVATE}' can also use"
      >&2 echo "  another local branch, '${LOCAL_BRANCH_RELEASE}', as a"
      >&2 echo "  reference, but that branch does not exist, either, e.g.:"
      >&2 echo "    \`git checkout -b ${LOCAL_BRANCH_RELEASE} <SHA>\`"
    fi
    >&2 echo "- The local branch '${branch_name}' can also use"
    >&2 echo "  the '${applied_tag}' tag to mark the rebase boundary"
    >&2 echo "  (which is usually managed by the git-put-wise-apply"
    >&2 echo "   command, but you can set it manually for this purpose),"
    >&2 echo "  e.g.:"
    >&2 echo "    \`git tag ${applied_tag} <SHA>\`"
  else
    >&2 echo "- The local branch '${branch_name}' pushes to"
    >&2 echo "  the remote branch '${remote_current}', but that branch"
    >&2 echo "  does not exist"
    >&2 echo "- The remote name is determined from the tracking branch, e.g.,"
    >&2 echo "    \`git branch -u <remote>/<branch>\`"
    if ${is_gpw_itself}; then
      >&2 echo "  Which you can override using the --remote CLI option,"
      >&2 echo "  or using the PW_OPTION_REMOTE environ."
    else
      >&2 echo "  Which you can override using the PW_OPTION_REMOTE environ."
    fi
    >&2 echo
    >&2 echo "- OPTION 4: If you don't plan to publish this project,"
    >&2 echo "  change the branch name to '${LOCAL_BRANCH_PRIVATE}' and use the"
    >&2 echo "  '${applied_tag}' tag to mark the rebase boundary"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi


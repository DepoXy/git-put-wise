#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

DRY_RUN=""
# DRY_RUN=__DRYRUN  # Uncomment to always dry-run, regardless -T|--dry-run.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_push_remotes () {
  ${PW_OPTION_DRY_RUN} && DRY_RUN="${DRY_RUN:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo

  git_insist_pristine

  must_not_be_patches_repo

  put_wise_push_remotes_go

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_push_remotes_go () {
  local git_push_force=""
  ! ${PW_OPTION_FORCE_PUSH} || git_push_force="--force-with-lease"

  local sort_from_commit=""
  local sortless_msg=""

  local local_release=""
  local remote_release=""
  local remote_protected=""
  local remote_current=""
  local remote_name=""

  local branch_name="$(git_branch_name)"

  local applied_tag="$(format_pw_tag_applied "${branch_name}")"

  if [ "${branch_name}" = "${LOCAL_BRANCH_PRIVATE}" ]; then
    local_release="${LOCAL_BRANCH_RELEASE}"
    remote_release="${REMOTE_BRANCH_RELEASE}"
    remote_protected="${REMOTE_BRANCH_SCOPING}"

    # The pw/in tag signifies the final patch from the latest --apply command.
    # It's the remote's HEAD, essentially (minus PRIVATE commits).
    # This is the fallback sort-from, in case there's no 'release' branch.
    # Note that this will move PRIVATE commits toward HEAD, but it'll
    # leave behind PROTECTED commits that may precede pw/work. (The
    # pw/work tag is the merge-base from the latest --apply command. It's
    # what the patches were based from, and it signifies what this host
    # pushed before that the remote added work to. I.e., when this host
    # pushed pw/work, it had just resorted, and PROTECTED commits were
    # bubbled toward pw/work. So if we wanted to move those commits
    # forward now, we'd have to set sort-from to a commit preceding
    # pw/work. Fortunately, we can use the 'release' branch, which
    # precedes these PROTECTED commits, as the sort-from base. Using
    # this tag is just fallback, but note that it means we won't move
    # earlier PROTECTED commits forward. Which we can a feature of not
    # having a 'release' branch.
    if git_tag_exists "${applied_tag}"; then
      sort_from_commit="${applied_tag}"
    fi

    if git_remote_branch_exists "${remote_protected}"; then
      # The --push host is considered the leader, and it will rebase as far
      # back as it takes to bubble up PROTECTED commits. The simplest case
      # is when there's a 'release' branch -- we'll pick that (below) as the
      # sort-from-commit, and we'll rebase all commits since 'release'.
      # But if there's no 'release' branch, there's not much point to having
      # PROTECTED commits, is there? And without the 'release' branch as
      # reference, it's less trivial to determine the sort-from-commit:
      # we could either rebase from the very first commit (easy solution),
      # or we could start walking from pw/work (with is the last --apply
      # command merge-base) -- because there are PROTECTED commits adjacent
      # to the pw/work tag. Walk from pw/work toward the root commit
      # until there are no more PROTECTED commits, and rebase from there,
      # and you'll bubble all the PROTECTED commits forward to HEAD. But this
      # sounds tedious, and doesn't seem like a feature anyone cares about
      # (surfacing PROTECTED commits in a repo that's not being published
      # (has no 'release' branch)). So we (I, the author) choose to leave
      # PROTECTED commits behind, abandoned, frozen in time if there's no
      # 'release' branch. If that's the case -- no 'release' reference --
      # we'll first fallback pw/applied, and then we'll fallback the
      # protected remote. Which, to be honest, generally ref. the same.
      if [ -z "${sort_from_commit}" ]; then
        sort_from_commit="${remote_protected}"
      fi
      # Always fetch the remote, so that our ref is current,
      # because this function also does a lot of state validating.
      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      pw_push_announce "Fetch from ‘${SCOPING_REMOTE_NAME}’"
      git fetch "${SCOPING_REMOTE_NAME}"
    else
      remote_protected=""
    fi

    # Prefer sorting from local or remote 'release' branch. This is easier
    # than walking from pw/work to see when scoping ends, and sorting from
    # there.
    if git_remote_branch_exists "${remote_release}"; then
      sort_from_commit="${remote_release}"
      # MAYBE/2023-01-18: GIT_FETCH: Use -q?
      pw_push_announce "Fetch from ‘${RELEASE_REMOTE_NAME}’"
      git fetch "${RELEASE_REMOTE_NAME}"
    else
      remote_release=""
    fi

    if git_branch_exists "${local_release}"; then
      sort_from_commit="${local_release}"
    else
      local_release=""
    fi

    # else, if sort_from_commit unset, will die after return from if-block.

    if [ -n "${remote_release}" ] && [ -n "${local_release}" ]; then
      # Verify 'release/release' is at or behind 'release'.
      local divergent_ok=false
      must_confirm_commit_at_or_behind_commit "${remote_release}" "${local_release}" \
        ${divergent_ok} "remote-release" "local-release"
      # Resort since 'release', which is guaranteed further along.
      sort_from_commit="${local_release}"
    fi

    # NOTE: If resorting since 'release' or 'publish/release', it means
    #       you will need to push --force 'entrust/scoping', and then
    #       on the @business device, you need to rebase on pull. Just
    #       how it works because you're managing so many unshareable
    #       forks.

    if [ -z "${sort_from_commit}" ]; then
      sortless_msg="$(echo -e \
        "Options:" \
        "\n- Use --apply command, so '${applied_tag}' tag gets set." \
        "\n- Push upstream to '${REMOTE_BRANCH_SCOPING}' branch." \
        "\n- Push upstream to '${REMOTE_BRANCH_RELEASE}' branch." \
        "\n- Create local '${LOCAL_BRANCH_RELEASE}' branch." \
        "\nComplete any one of these activities and then you may --push." \
      )"
    fi

  elif [ "$(git_branch_name)" = "${LOCAL_BRANCH_RELEASE}" ]; then
    # Because we rebase to reorder scoping commits, we need to identify
    # a starting ref. Without a starting ref, it gets complicated (do
    # we resort everything? Do we find the first PROTECTED or PRIVATE
    # commit and rebase from there?). It's easier to tell the user to
    # make the first push.
    must_verify_remote_branch_exists "${REMOTE_BRANCH_RELEASE}"

    # So that merge-base is accurate.
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    pw_push_announce "Fetch from ‘${RELEASE_REMOTE_NAME}’"
    git fetch "${RELEASE_REMOTE_NAME}"

    sort_from_commit="${REMOTE_BRANCH_RELEASE}"

    remote_release="${REMOTE_BRANCH_RELEASE}"
  else
    # $(git_branch_name) not 'release'|'protected'|'private'.
    # - Note that push.default defaults to 'simple', which pushes to upstream
    #   tracking branch when pushing to that remote, otherwise works like
    #   push.default 'current', which uses same name for pushing.
    #   - For feature branches, I like to track the trunk, so git-pull
    #     rebases appropriately. But I like push.default 'current', so
    #     that push uses the same feature branch name that I use locally.
    # - The following effectively mimics 'current'.
    local tracking_branch
    tracking_branch="$(git_tracking_branch)"

    remote_name="${PW_OPTION_REMOTE}"

    if [ -z "${remote_name}" ]; then
      remote_name="$(git_upstream_parse_remote_name "${tracking_branch}")"
    fi

    if [ -z "${remote_name}" ]; then
      >&2 echo "ERROR: Cannot determine push remote." \
        "Either set tracking branch to remote branch, or use --remote."

      exit 1
    fi

    pw_push_announce "Fetch from ‘${remote_name}’"
    # MAYBE/2023-01-18: GIT_FETCH: Use -q?
    git fetch "${remote_name}"

    remote_current="${remote_name}/${branch_name}"

    if ! ${PW_OPTION_FORCE_PUSH} && git_remote_branch_exists "${remote_current}"; then
      sort_from_commit="${remote_current}"
    else
      # Similarly to the 'release' branch, which dies if no 'publish/release'
      # yet, here we die if there's not upstream ref, either. But this path
      # will likely not happen for new feature branches so long as the user
      # uses a tracking branch. E.g., consider a new branch was made like this:
      #   git checkout -b feature/abc && git branch -u origin/main
      # Then when you first call `put-wise --archive`, this if-block runs,
      # and we'll set sort_from_commit to origin/main.
      must_verify_remote_branch_exists "${tracking_branch}"

      sort_from_commit="${tracking_branch}"
    fi
  fi

  if [ -z "${sort_from_commit}" ]; then
    ${PW_OPTION_FAIL_ELEVENSES} && exit ${PW_ELEVENSES}

    >&2 echo "ERROR: Nothing upstream identified for project: “$(pwd -L)”"
    >&2 echo "- Branch: “$(git_branch_name)”"
    if [ -n "${sortless_msg}" ]; then
      >&2 echo -e "${sortless_msg}"
    else
      >&2 echo "You may need to get things rolling by initiating the first push."
    fi

    exit 1
  fi

  # ***

  # Overzealous UX reporting if diverging from tags, not sure why I care
  # to alert user.

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

  # ***

  # Note that confirm_state checks sort-from shares history with HEAD:
  #   must_confirm_commit_at_or_behind_commit "${sort_from_commit}" "HEAD"

  >&2 debug "sort_from_commit: ${sort_from_commit}"

  if ! git_is_same_commit "${sort_from_commit}" "HEAD"; then
    pw_push_announce "Resorting scoped commits"
    confirm_state_and_resort_to_prepare_branch "${sort_from_commit}"
  fi

  # ***

  local release_boundary_or_HEAD
  release_boundary_or_HEAD="$( \
    identify_scope_ends_at "^${SCOPING_PREFIX}" "^${PRIVATE_PREFIX}" \
  )"

  local protected_boundary_or_HEAD
  protected_boundary_or_HEAD="$( \
    identify_scope_ends_at "^${PRIVATE_PREFIX}" \
  )"

  # It's assumed you control the 'release' branch and that you wouldn't
  # be using this script otherwise, which is why we just move this pointer.
  if [ -n "${local_release}" ] || [ -n "${remote_release}" ]; then
    if [ "$(git_branch_name)" != "${LOCAL_BRANCH_RELEASE}" ]; then
      pw_push_announce "Move ‘${LOCAL_BRANCH_RELEASE}’ HEAD"
      git_force_branch "${LOCAL_BRANCH_RELEASE}" "${release_boundary_or_HEAD}"
    fi
  fi

  # ***

  # Temporary pw-private/pw-protected scoping tags. For user, not for code.
  # - So sad that `tig` doesn't show these characters:
  #    PW_TAG_SCOPE_MARKER_PRIVATE="pw-🥷"
  #    PW_TAG_SCOPE_MARKER_PROTECTED="pw-🧚"
  PW_TAG_SCOPE_MARKER_PRIVATE="pw-🔴"
  PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔵"
  # Here's a test tag to show which characters display properly in @linux tig:
  #   PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔴🟠🟡🟢🔵🟣🟤⚫⚪🟥🟧🟨🟩🟦🟪🟫⬛⬜"
  #                             @linux: ^^      ^^    ^^^^              ^^^^

  # These all show up in tig @linux: pw-🚩🏁🔀
  PW_TAG_SCOPE_PUSHES_PREFIX="pw-🚩"
  PW_TAG_SCOPE_PUSHES_RELEASE="${PW_TAG_SCOPE_PUSHES_PREFIX}-${RELEASE_REMOTE_BRANCH}"
  PW_TAG_SCOPE_PUSHES_SCOPING="${PW_TAG_SCOPE_PUSHES_PREFIX}-${SCOPING_REMOTE_NAME}"
  PW_TAG_SCOPE_PUSHES_THEREST="${PW_TAG_SCOPE_PUSHES_PREFIX}-${branch_name}"

  # Skip ${DRY_RUN}, tags no biggie, and user wants to see in tig.
  git tag -f "${PW_TAG_SCOPE_MARKER_PRIVATE}" "${protected_boundary_or_HEAD}" > /dev/null
  git tag -f "${PW_TAG_SCOPE_MARKER_PROTECTED}" "${release_boundary_or_HEAD}" > /dev/null

  local tagged_release=""
  local tagged_scoping=""

  local remote_scoping_branch=""

  if [ -n "${remote_release}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_RELEASE}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_release="${PW_TAG_SCOPE_PUSHES_RELEASE}"
  fi
  if [ -n "${remote_protected}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_SCOPING}" "${protected_boundary_or_HEAD}" > /dev/null
    tagged_scoping="${PW_TAG_SCOPE_PUSHES_SCOPING}"
    remote_scoping_branch="${SCOPING_REMOTE_NAME}/${SCOPING_REMOTE_BRANCH}"
  fi
  if [ -n "${remote_current}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_THEREST}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_scoping="${PW_TAG_SCOPE_PUSHES_THEREST}"
    remote_scoping_branch="${remote_name}/${branch_name}"
  fi

  # ***

  if prompt_user_to_continue_update_remotes \
    "${tagged_release}" "${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}" \
    "${tagged_scoping}" "${remote_scoping_branch}" \
  ; then
    if ! prompt_user_to_review_action_plan_using_tig; then
      >&2 echo "${PW_USER_CANCELED_GOODBYE}"
    else
      if prompt_user_to_continue_push_remote_branch "${remote_release}"; then
        announce_git_push "${RELEASE_REMOTE_BRANCH}"
        ${DRY_RUN} git push "${RELEASE_REMOTE_NAME}" \
          "${release_boundary_or_HEAD}:refs/heads/${RELEASE_REMOTE_BRANCH}" ${git_push_force}
      fi

      if prompt_user_to_continue_push_remote_branch "${remote_protected}"; then
        announce_git_push "${SCOPING_REMOTE_BRANCH}"
        ${DRY_RUN} git push "${SCOPING_REMOTE_NAME}" \
          "${protected_boundary_or_HEAD}:refs/heads/${SCOPING_REMOTE_BRANCH}" ${git_push_force}
      fi

      if prompt_user_to_continue_push_remote_branch "${remote_current}"; then
        announce_git_push "${branch_name}"
        ${DRY_RUN} git push "${remote_name}" \
          "${release_boundary_or_HEAD}:refs/heads/${branch_name}" ${git_push_force}
      fi
    fi
  fi

  # ***

  quietly_delete_tag () {
    git tag -d "$1" > /dev/null 2>&1 || true
  }

  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PRIVATE}"
  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PROTECTED}"

  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_RELEASE}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_SCOPING}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_THEREST}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

must_verify_remote_branch_exists () {
  local remote_branch="$1"

  ( [ -z "${remote_branch}" ] || ! git_remote_branch_exists "${remote_branch}" ) \
    || return 0

  >&2 echo "ERROR: Where's remote branch “${remote_branch}”?"
  >&2 echo "- Nothing to do for project: “$(pwd -L)”"
  >&2 echo "(We use remote to set scoping rebase starting ref," \
    "and we'd rather not rebase from the first commit nor ask" \
    "you where to start from, so we let you make the first push," \
    "and then we'll use that upstream the next time you call us." \
    "Alternatively, if this is not a special branch" \
    "('${LOCAL_BRANCH_PRIVATE}' or '${LOCAL_BRANCH_RELEASE}')" \
    "you can set a \`git branch -u <>\` upstream tracking branch" \
    "and we'll use that as the rebase-resort start reference."

  exit 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

pw_push_announce () {
  echo "$(fg_lightblue)$(bg_myrtle)${1}$(attr_reset)"
}

announce_git_push () {
  local branch="$1"

  pw_push_announce "Sending ‘${branch}’"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_force_branch () {
  local branch_name="$1"
  local start_point="$2"

  if git_branch_exists "${branch_name}"; then
    ${DRY_RUN} git branch -f --no-track "${branch_name}" "${start_point}"
  else
    # Might as well make a local branch, eh.
    ${DRY_RUN} git branch "${branch_name}" "${start_point}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_user_to_continue_update_remotes () {
  local tagged_release="$1"
  local remote_release_branch="$2"
  local tagged_scoping="$3"
  local remote_scoping_branch="$4"

  # Contract-by-design assertion that author didn't make a DEV misstep.
  if [ -z "${tagged_release}" ] && [ -z "${tagged_scoping}" ]; then
    >&2 echo "ERROR: prompt_user_to_continue_update_remotes: Nothing tagged?"

    exit 1
  fi

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  # COPYD: See similar `print_tig_review_instructions` function(s) elsewhere.
  print_tig_review_instructions () {
    echo "Please review and confirm the *push plan*"
    echo
    echo "We'll run tig, and you can look for these tag(s) in the revision history:"
    echo
    local pushed_to_msg="This revision will be pushed to"
    if [ -n "${tagged_release}" ]; then
      echo "  <${tagged_release}> — ${pushed_to_msg} ${remote_release_branch}"
    fi
    if [ -n "${tagged_scoping}" ]; then
      echo "  <${tagged_scoping}> — ${pushed_to_msg} ${remote_scoping_branch}"
    fi
    echo
    echo "Then press 'w' to confirm the plan and push"
    echo "- Or press 'q' to quit tig and cancel everything"
    tig_prompt_print_skip_hint
  }
  print_tig_review_instructions

  tig_prompt_confirm_launching_tig
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_user_to_continue_push_remote_branch () {
  local remote_branch="$1"

  [ -n "${remote_branch}" ] || return 1

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  printf "Would you like to push “${remote_branch}”? [y/N] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "n" "y"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi


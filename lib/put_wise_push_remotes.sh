#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

DRY_ECHO=""
# DRY_ECHO=__DRYRUN  # Uncomment to always dry-run, regardless -T|--dry-run.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_push_remotes () {
  ${PW_OPTION_DRY_RUN:-false} && DRY_ECHO="${DRY_ECHO:-__DRYRUN}"

  local before_cd="$(pwd -L)"

  # Side effect: `cd`'s, and updates PW_PROJECT_PATH, to canonicalize.
  must_cd_project_path_and_verify_repo

  must_not_be_patches_repo

  put_wise_push_remotes_go

  cd "${before_cd}"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

put_wise_push_remotes_go () {
  local git_push_force=""
  ! ${PW_OPTION_FORCE_PUSH:-false} || git_push_force="--force-with-lease"

  # ***

  # Prints errors and exits 1 if no releast boundary can
  # be identified and the commits are not sorted & signed.
  # (Or exits 11 without printing errors if -11 option used.)
  # The following vars are set by the sort_from_commit, etc., susser:
  local branch_name=""
  local local_release=""
  local remote_release=""
  local remote_liminal=""
  local remote_protected=""
  local remote_current=""
  local remote_name=""
  local sort_from_commit=""
  # CXREF: ~/.kit/git/git-put-wise/lib/dep_rebase_boundary.sh
  put_wise_identify_rebase_boundary_and_remotes "push"

  # ***

  # Note that resort_and_sign_commits_before_push checks that
  # sort-from shares history with HEAD:
  #   must_confirm_commit_at_or_behind_commit "${sort_from_commit}" "HEAD"

  >&2 debug "sort_from_commit: ${sort_from_commit}"

  if ! git_is_same_commit "${sort_from_commit}" "HEAD"; then
    # Exits 0/11 if sort_from_commit is HEAD.
    resort_and_sign_commits_before_push "${sort_from_commit}" \
      ${_enable_gpg_sign:-true}
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
  if [ -n "${local_release}" ]; then
    # local_release non-empty iff current branch is LOCAL_BRANCH_PRIVATE
    # (so this if-check always passes).
    if [ "$(git_branch_name)" != "${LOCAL_BRANCH_RELEASE}" ]; then
      if git merge-base --is-ancestor \
        "${LOCAL_BRANCH_RELEASE}" "${release_boundary_or_HEAD}" \
      ; then
        echo_announce "Move ‘${LOCAL_BRANCH_RELEASE}’ HEAD"

        git_force_branch "${LOCAL_BRANCH_RELEASE}" "${release_boundary_or_HEAD}"
        # MAYBE/2023-12-03: Restore branch pointer if git-push canceled/fails?
      else
        # See also: must_confirm_commit_at_or_behind_commit
        >&2 warn "BWARE: Not moving ‘${LOCAL_BRANCH_RELEASE}’ HEAD, because it is"
        >&2 warn "  not an ancestor of the release boundary:"
        >&2 warn "    ${release_boundary_or_HEAD}"
        >&2 warn "- This means the ‘${LOCAL_BRANCH_RELEASE}’ branch includes scoped commits!"
        >&2 warn "  - I.e., commit messages that start with \"${SCOPING_PREFIX}\" or \"${PRIVATE_PREFIX}\""
      fi
    fi
  fi

  # ***

  # Temporary pw-private/pw-protected scoping tags. For user, not for code.
  # - Note that some characters will not claim their full width in the
  #   terminal (including tig) such as 🛡 or 🛡️. Odder, some might show up
  #   in the terminal but appear blank in tig, such as 🥷 (on author's @linux).
  #   - Just FYI that you should `git tag test-🥷-me` aforehand.
  PW_TAG_SCOPE_MARKER_PRIVATE="pw-🔴"
  PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔵"
  # Here's a test tag to show which characters display properly in @linux tig:
  #   PW_TAG_SCOPE_MARKER_PROTECTED="pw-🔴🟠🟡🟢🔵🟣🟤⚫⚪🟥🟧🟨🟩🟦🟪🟫⬛⬜"
  #                             @linux: ^^      ^^    ^^^^              ^^^^
  #                             @macOS: ^^      ^^
  # NOTED/2024-06-23: @macOS tig doesn't render these all, either, even
  # with ncusrsw support.
  # - The terminal shows these characters, though. E.g., echo the line above
  #   to iTerm2 or Kitty and it looks good, and echoed to Alacritty it looks
  #   mostly good, but Alacritty uses the simpler black and white VS15 variation
  #   selector for some symbols, e.g., ⚫ and ⚪ print as ⚫︎and ⚪︎ (though when
  #   you copy-paste from Alacritty to another app, they appear VS16 again).
  #   - REFER: https://en.wikipedia.org/wiki/Variation_Selectors_(Unicode_block)
  #            https://en.wikipedia.org/wiki/Miscellaneous_Symbols
  # - But when you commit these symbols to Git and view in tig, many of them
  #   are simply absent/blank. And if you copy from the text from tig and
  #   paste elsewhere, you'll see the symbols have been replaced with spaces.
  # - See OMR tig build, which supports wide-char:
  #     ~/.depoxy/ambers/home/.kit/git/_mrconfig-git-core
  #   - But only 🔴 and 🔵 are visible.

  # Use different flags for different branches: release, liminal, scoping, therest.
  # - SAVVY: Test new emoji b/c not all visible in tig ... # ↓↓↓↓↓ These all visible in tig @linux
  #   - On @macOS, below are all visible in tig except: 🧚⛔⛓️
  PW_TAG_PREFIX_RELEASE="${PW_TAG_PREFIX_RELEASE:-pw-📢}"  # 📢🚀
  PW_TAG_PREFIX_LIMINAL="${PW_TAG_PREFIX_LIMINAL:-pw-💥}"  # 🔥🌀💥🎯🧚
  PW_TAG_PREFIX_SCOPING="${PW_TAG_PREFIX_SCOPING:-pw-💪}"  # 🔰💪🔐🔒🔏🔑🔓⛔🙌🤐🛑👇⛓️
  PW_TAG_PREFIX_THEREST="${PW_TAG_PREFIX_THEREST:-pw-🚩}"  # 🚩🏁🔀
  PW_TAG_SCOPE_PUSHES_RELEASE="${PW_TAG_PREFIX_RELEASE}-${RELEASE_REMOTE_BRANCH}"
  PW_TAG_SCOPE_PUSHES_LIMINAL="${PW_TAG_PREFIX_LIMINAL}-${LIMINAL_REMOTE_BRANCH}"
  PW_TAG_SCOPE_PUSHES_SCOPING="${PW_TAG_PREFIX_SCOPING}-${SCOPING_REMOTE_NAME}"
  PW_TAG_SCOPE_PUSHES_THEREST="${PW_TAG_PREFIX_THEREST}-${branch_name}"

  # Skip ${DRY_ECHO}, tags no biggie, and user wants to see in tig.
  git tag -f "${PW_TAG_SCOPE_MARKER_PRIVATE}" "${protected_boundary_or_HEAD}" > /dev/null
  git tag -f "${PW_TAG_SCOPE_MARKER_PROTECTED}" "${release_boundary_or_HEAD}" > /dev/null

  local tagged_release=""
  local tagged_liminal=""
  local tagged_scoping=""
  local tagged_current=""

  if [ -n "${remote_release}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_RELEASE}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_release="${PW_TAG_SCOPE_PUSHES_RELEASE}"
  fi

  if [ -n "${remote_liminal}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_LIMINAL}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_liminal="${PW_TAG_SCOPE_PUSHES_LIMINAL}"
  fi

  if [ -n "${remote_protected}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_SCOPING}" "${protected_boundary_or_HEAD}" > /dev/null
    tagged_scoping="${PW_TAG_SCOPE_PUSHES_SCOPING}"
  fi

  if [ -n "${remote_current}" ]; then
    git tag -f "${PW_TAG_SCOPE_PUSHES_THEREST}" "${release_boundary_or_HEAD}" > /dev/null
    tagged_current="${remote_name}/${branch_name}"
  fi

  # ***

  # Don't errexit on git-push failure until after cleaning up tags.
  local keep_going=false

  handle_push_failed () {
    local remote_branch="$1"

    keep_going=false

    local ornament="$(fg_lightyellow)$(bg_myrtle)"

    echo "${ornament}ERROR: Push failed! denied by ‘${remote_branch}’$(attr_reset)"
  }

  # In the prompt_user call, note that we have "<remote>/<branch>" vars.
  # already, e.g., we could use ${remote_release} instead of the complete
  #   ${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}
  # but the latter matches the git-push command, so using that for matchability.

  if prompt_user_to_continue_update_remotes \
    "${tagged_release}" "${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}" \
    "${tagged_liminal}" "${LIMINAL_REMOTE_NAME}/${LIMINAL_REMOTE_BRANCH}" \
    "${tagged_scoping}" "${SCOPING_REMOTE_NAME}/${SCOPING_REMOTE_BRANCH}" \
    $(test -z "${remote_current}" || printf "%s" "${tagged_current}") \
      $(test -z "${remote_current}" || printf "%s" "${remote_name}/${branch_name}") \
  ; then
    # Add 'r' command to restrict push just to 'release'.
    # - Useful when 'liminal' or 'entrust' diverged, and
    #   user didn't use <Ctrl-f> force-push.
    local restrict_release=false
    # - SAVVY: Override tig's built-in `r` — 'view-refs'
    # - COPYD: Similar to lib/tig/config-put-wise
    #   - CXREF: ~/.kit/git/git-put-wise/lib/tig/config-put-wise
    # - SAVVY: The `echo > ${REPLY_PATH}` is reingested as GPW_TIG_PROMPT_CONTENT.
    local restrict_release_binding="\
bind generic r +<sh -c \" \\
 git_put_wise__prompt__r_for_release_branch () { \\
    REPLY_PATH=\\\"\${PW_PUSH_TIG_REPLY_PATH:-.gpw-yes}\\\"; \\
    if [ ! -e \\\"\${REPLY_PATH}\\\" ]; then \\
      echo \\\"${remote_release}\\\" > \\\"\${REPLY_PATH}\\\"; \\
    else \\
      >&2 echo \\\"ERROR: Already exists: \${REPLY_PATH}\\\"; \\
    fi; \\
  }; git_put_wise__prompt__r_for_release_branch\"
    "

    # Side-effect: Caller sets GPW_TIG_PROMPT_CONTENT.
    if prompt_user_to_review_action_plan_using_tig "${restrict_release_binding}"; then
      keep_going=true

      if [ "${GPW_TIG_PROMPT_CONTENT}" = "${remote_release}" ]; then
        restrict_release=true
      fi
    else
      >&2 echo "${PW_USER_CANCELED_GOODBYE}"
    fi

    if ${keep_going}; then
      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_release}"; then
        echo_announce_push "${RELEASE_REMOTE_BRANCH}"
        ${DRY_ECHO} git push "${RELEASE_REMOTE_NAME}" \
          "${release_boundary_or_HEAD}:refs/heads/${RELEASE_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${RELEASE_REMOTE_NAME}/${RELEASE_REMOTE_BRANCH}"
      fi
    fi

    if ${keep_going} && ! ${restrict_release}; then
      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_liminal}"; then
        echo_announce_push "${LIMINAL_REMOTE_BRANCH}"
        ${DRY_ECHO} git push "${LIMINAL_REMOTE_NAME}" \
          "${release_boundary_or_HEAD}:refs/heads/${LIMINAL_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${LIMINAL_REMOTE_NAME}/${LIMINAL_REMOTE_BRANCH}"
      fi

      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_protected}"; then
        echo_announce_push "${SCOPING_REMOTE_BRANCH}"
        ${DRY_ECHO} git push "${SCOPING_REMOTE_NAME}" \
          "${protected_boundary_or_HEAD}:refs/heads/${SCOPING_REMOTE_BRANCH}" ${git_push_force} \
            || handle_push_failed "${SCOPING_REMOTE_NAME}/${SCOPING_REMOTE_BRANCH}"
      fi

      if prompt_user_to_continue_push_remote_branch ${keep_going} "${remote_current}"; then
        echo_announce_push "${branch_name}"
        ${DRY_ECHO} git push "${remote_name}" \
          "${release_boundary_or_HEAD}:refs/heads/${branch_name}" ${git_push_force} \
            || handle_push_failed "${remote_name}/${branch_name}"
      fi
    fi
  fi

  if ! ${keep_going}; then
    echo_announce "Canceled put-wise-push"
  fi

  # ***

  quietly_delete_tag () {
    git tag -d "$1" > /dev/null 2>&1 || true
  }

  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PRIVATE}"
  quietly_delete_tag "${PW_TAG_SCOPE_MARKER_PROTECTED}"

  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_RELEASE}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_LIMINAL}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_SCOPING}"
  quietly_delete_tag "${PW_TAG_SCOPE_PUSHES_THEREST}"

  # Indicate success/failure.
  ${keep_going}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

echo_announce_push () {
  local branch="$1"

  echo_announce "Sending ‘${branch}’"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

git_force_branch () {
  local branch_name="$1"
  local start_point="$2"

  if git_branch_exists "${branch_name}"; then
    ${DRY_ECHO} git branch -f --no-track "${branch_name}" "${start_point}"
  else
    # Might as well make a local branch, eh.
    ${DRY_ECHO} git branch "${branch_name}" "${start_point}"
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

prompt_user_to_continue_update_remotes () {
  local something_tagged=false

  local orig_count="$#"

  local remote_names=""

  while [ $# -gt 0 ]; do
    local tagged_name="$1"
    local remote_branch_nickname="$2"

    if ! shift 2; then
      >&2 echo "GAFFE: prompt_user_to_continue_update_remotes:" \
        "Uneven arg count (${orig_count})"

      exit 1
    fi

    if [ -n "${tagged_name}" ]; then
      something_tagged=true
    fi

    [ -z "${remote_names}" ] || remote_names="${remote_names}\n"
    remote_names="${remote_names}    ${remote_branch_nickname}"
  done

  if ! ${something_tagged}; then
    >&2 echo "ABORT: Cannot push, because no remote branch identified from candidates:"
    >&2 echo -e "${remote_names}"
    >&2 echo "- Hint: If you have not pushed yet, do so manually the first time"
    >&2 echo "  - Or, if this is a private repo without a push remote,"
    >&2 echo "    try the ‘archive’ command"

    exit 1
  fi

  # ***

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  # COPYD: See similar `print_tig_review_instructions` function(s) elsewhere.
  print_tig_review_instructions () {
    echo "Please review and confirm the *push plan*"
    echo
    echo "We'll run tig, and you can look for these tag(s) in the revision history:"
    echo

    local pushed_to_msg="This revision will be pushed to"

    local n_args=0
    for arg in "$@"; do
      local tagged_name="$1"
      local remote_branch_nickname="$2"

      if [ -n "${tagged_name}" ]; then
        echo "  <${tagged_name}> — ${pushed_to_msg} ${remote_branch_nickname}"
      fi
    done

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
  local keep_going="$1"
  local remote_branch="$2"

  ${keep_going} || return 1

  [ -n "${remote_branch}" ] || return 1

  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  printf "Would you like to push “${remote_branch}”? [y/N] "

  local key_pressed
  local opt_chosen
  prompt_read_single_keypress "n" "y"
  [ "${opt_chosen}" = "y" ] && return 0 || return 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE[0]}" ]; then
  >&2 echo "😶"
fi


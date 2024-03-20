#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_PUSH_TIG_REPLY_PATH=".gpw-yes"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Add a custom tig command using a shim config and tig's `source` command.
# - If you're using DepoXy, the custom tig command is found at:
#     ~/.kit/git/git-put-wise/lib/tig/config-put-wise
# - We build a temporary tig config at
#     ~/.kit/git/git-put-wise/lib/tig/config
#   that `source`'s both the user's normal tig config,
#   and then our special command.
# - The special command, wired to 'w' (one of the few unbound keys
#   that's available, but also complements the 'w' command in git
#   interactive-rebase-tool, which is nice, I appreciate parity)
#   lets the users confirm the put-wise push plan from tig.
#   - So we'll run tig, and the user will review the temporary tags
#     to see what commits will be pushed, and then then can 'q' to quit
#     tig like normal and cancel the push, or the user can use temp. 'w'
#     command to complete the push.
prompt_user_to_review_action_plan_using_tig () {
  local custom_cfg="$1"

  ! ${PW_OPTION_AUTO_CONFIRM:-false} || return 0

  local approved=false

  # E.g., ".gpw-yes", where tig 'w' command indicates user pressed 'w'.
  export PW_PUSH_TIG_REPLY_PATH

  path_not_exists "${PW_PUSH_TIG_REPLY_PATH}" \
    "prompt_user_to_review_action_plan_using_tig" \
    || return 1

  # Make path to put-wise source lib/ (e.g., ~/.kit/git/git-put-wise/lib/
  # if you run DepoXy) using $0 process path, which might be, e.g.,
  # ~/.local/bin/git-put-wise, and symlinks git-put-wise/bin/git-put-wise.
  local pw_lib="$(dirname -- "$(realpath -- "$0")")/../lib"

  local old_shim_cfg
  local shim_cfg
  shim_cfg="$(prepare_shim_tig_config "${pw_lib}" "${custom_cfg}")" \
    || return 1

  XDG_CONFIG_HOME="${pw_lib}" tig

  /bin/rm "${shim_cfg}"

  if [ -f "${old_shim_cfg}" ] \
    && diff -q "${shim_cfg}" "${old_shim_cfg}" >/dev/null \
  ; then
    /bin/rm "${old_shim_cfg}"
  elif [ -n "${old_shim_cfg}" ]; then
    >&2 echo "ALERT: Moved old shim cfg: ‘${old_shim_cfg}’ (unrecognized)"
  fi

  if [ -f "${PW_PUSH_TIG_REPLY_PATH}" ]; then
    approved=true

    /bin/rm "${PW_PUSH_TIG_REPLY_PATH}"
  fi

  ${approved}
}

prepare_shim_tig_config () {
  local pw_lib="$1"
  local custom_cfg="$2"

  local shim_cfg="${pw_lib}/tig/config"

  if [ -e "${shim_cfg}" ]; then
    # Should mean user killed `tig` prompt and we didn't cleanup.
    old_shim_cfg="${shim_cfg}-$(date +%Y%m%d%H%M%S)"

    command mv -i "${shim_cfg}" "${old_shim_cfg}"
  fi

  truncate -s 0 -- "${shim_cfg}"

  # - Per `man tig`, tig sources first config it finds in order:
  #   $XDG_CONFIG_HOME/tig/config, ~/.config/tig/config, ~/.tigrc.
  local user_cfg
  for user_cfg in \
    "${XDG_CONFIG_HOME}" \
    "${HOME}/.config/tig/config" \
    "${HOME}/.tigrc" \
  ; do
    if [ -f "${user_cfg}" ]; then
      echo "source ${user_cfg}" > "${shim_cfg}"

      break
    fi
  done

  # NOTE: tig does not appreciate double quotes around the path.
  echo "source ${pw_lib}/tig/config-put-wise" >> "${shim_cfg}"

  [ -z "${custom_cfg}" ] || echo "${custom_cfg}" >> "${shim_cfg}"

  printf "${shim_cfg}"
}

# ***

path_not_exists () {
  local target="$1"
  local caller="$2"

  if [ -e "${target}" ]; then
    >&2 echo "ERROR: Did not expect to find something at ${target} [${caller}]"

    return 1
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

tig_prompt_print_skip_hint () {
  ! ${PW_OPTION_QUICK_TIG:-false} || return 0

  echo
  echo "HINT: You can skip this prompt. Use an environ or CLI option:"
  echo "  [PW_OPTION_QUICK_TIG=true] $(basename -- "$0") [-E/--no-explain]"
}

tig_prompt_print_launch_confirmation () {
  echo
  echo "- Press 'y', 'Enter', or 'space' to launch tig"
  echo "  - Then press 'w' to approve or 'q' to cancel"
  echo
  printf "             [Y/n] "
}

tig_prompt_confirm_launching_tig () {
  tig_prompt_print_launch_confirmation

  local key_pressed
  local opt_chosen
  local print_newline=false
  prompt_read_single_keypress "y" "n" ${print_newline}

  # tig prints a newline on exit, but this code path
  # doesn't run tig, so compensate.
  [ "${key_pressed}" = $'\n' ] || printf '\n'

  if [ "${opt_chosen}" = "y" ]; then
    return 0
  else
    return 1
  fi
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi


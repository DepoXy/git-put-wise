#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_VERSION="git-put-wise version 1.0.0"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Command line actions and their arguments (options) are parsed and
# stored internally as environment variables.
#
# - User are free to use the corresponding environ instead of using
#   the command line argument, although in practice users are only
#   likely interested in a few of these.

# *** Environs that users might specify from their Bashrc, or similar

# Path to directory (repo) containing archives
# made by the --patches option.
PW_PATCHES_REPO="${PW_PATCHES_REPO}"

PW_OPTION_PASS_NAME="${PW_OPTION_PASS_NAME}"

PW_OPTION_QUICK_TIG=${PW_OPTION_QUICK_TIG:-false}

PW_OPTION_APPLY_AUTHOR_NAME="${PW_OPTION_APPLY_AUTHOR_NAME}"
PW_OPTION_APPLY_AUTHOR_EMAIL="${PW_OPTION_APPLY_AUTHOR_EMAIL}"
PW_OPTION_RESET_AUTHOR_DISABLE=${PW_OPTION_RESET_AUTHOR_DISABLE:-false}

# *** Other environs that users will be less likely to care about

# Path to project to push from or pull into.
# Defaults to current directory.
PW_PROJECT_PATH="${PW_PROJECT_PATH}"

# The action is indicated internally using these flags.
# - Obviously only one of these will be true at runtime.
PW_ACTION_PUSH=${PW_ACTION_PUSH:-false}
PW_ACTION_PULL=${PW_ACTION_PULL:-false}
PW_ACTION_ARCHIVE=${PW_ACTION_ARCHIVE:-false}
PW_ACTION_APPLY=${PW_ACTION_APPLY:-false}
PW_ACTION_APPLY_ALL=${PW_ACTION_APPLY_ALL:-false}
PW_ACTION_RESET=${PW_ACTION_RESET:-false}
PW_ACTION_SHA=${PW_ACTION_SHA:-false}
# - If action does not complete, user must --continue or --abort.
PW_ACTION_REBASE_CONTINUE=${PW_ACTION_REBASE_CONTINUE:-false}
PW_ACTION_REBASE_ABORT=${PW_ACTION_REBASE_ABORT:-false}
# - Rebase-todo 'exec' actions not meant to be called by user.
PW_ACTION_PULL_CLEANUP=${PW_ACTION_PULL_CLEANUP:-false}

PW_OPTION_NO_CLEANUP=${PW_OPTION_NO_CLEANUP:-false}

PW_OPTION_FORCE_PUSH=${PW_OPTION_FORCE_PUSH:-false}
PW_OPTION_USE_LIMINAL=${PW_OPTION_USE_LIMINAL:-false}
PW_OPTION_AUTO_CONFIRM=${PW_OPTION_AUTO_CONFIRM:-false}

PW_OPTION_SKIP_SQUASH=${PW_OPTION_SKIP_SQUASH:-false}

PW_OPTION_STARTING_REF="${PW_OPTION_STARTING_REF}"

PW_OPTION_BRANCH="${PW_OPTION_BRANCH}"
PW_OPTION_REMOTE="${PW_OPTION_REMOTE}"

PW_OPTION_REGENERATE_RECEIPTS=${PW_OPTION_REGENERATE_RECEIPTS}

PW_OPTION_VERBOSE=${PW_OPTION_VERBOSE:-false}

PW_OPTION_DRY_RUN=${PW_OPTION_DRY_RUN:-false}

PW_OPTION_FAIL_ELEVENSES=${PW_OPTION_FAIL_ELEVENSES:-false}

# *** Environs without command line arguments

# This is loosely tied to --verbose, but not directly settable via CLI arg.
PW_LOG_LEVEL="${PW_LOG_LEVEL}"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

source_deps () {
  source_dep "lib/cli_help_usage.sh"
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

cli_parse_params () {
  local project_path_arg_seen=false

  while [ "$1" != '' ]; do
    if [ "$1" = '--' ]; then
      shift

      break
    fi

    # Avail  a b c d e f g h i j k l m n o p q r s t u v w x y z
    # ↓↓↓↓↓  ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓
    # lower:       d       h   j k   m     p q   s t     w x   z
    # upper:   B   D     G H I   K         P Q         V W X Y Z

    case $1 in
      -h | --help | help)
        # Note the `git put-wise --help` is processed by `git`,
        # but not `git put-wise help`.
        echo "${PW_USAGE}"

        exit 0
        ;;

      -V | --version)
        echo "${PW_VERSION}"

        exit 0
        ;;

      --about | about)
        source_dep "lib/cli_help_about.sh"

        echo "${PW_ABOUT}"

        exit 0
        ;;

      -o | --push | push)
        PW_ACTION_PUSH=true

        shift
        ;;

      -i | --pull | pull)
        PW_ACTION_PULL=true

        shift
        ;;

      -e | --archive | archive)
        PW_ACTION_ARCHIVE=true

        shift
        ;;

      -a | --apply | apply)
        PW_ACTION_APPLY=true

        shift
        ;;

      -A | --apply-all | apply-all | all)
        PW_ACTION_APPLY_ALL=true

        shift
        ;;

      -R | --reset)
        PW_ACTION_RESET=true

        shift
        ;;

      --sha | sha)
        PW_ACTION_SHA=true

        shift
        ;;

      --continue | continue)
        PW_ACTION_REBASE_CONTINUE=true

        shift
        ;;

      --abort | abort)
        PW_ACTION_REBASE_ABORT=true

        shift
        ;;

      # Internal/private func. (called via rebase-todo 'exec').
      put_wise_pull_remotes_cleanup)
        PW_ACTION_PULL_CLEANUP=true

        # Clear $@, so `-- $1` not assumed below.
        set --

        break
        ;;

      -J | --project-path)
        option_value_must_be_specified "$@"
        PW_PROJECT_PATH="$2"

        shift 2
        ;;

      -O | --patches-repo)
        option_value_must_be_specified "$@"
        PW_PATCHES_REPO="$2"

        shift 2
        ;;

      -n | --pass-name)
        option_value_must_be_specified "$@"
        PW_OPTION_PASS_NAME="$2"

        shift 2
        ;;

      -c | --cleanup)
        PW_OPTION_NO_CLEANUP=false

        shift
        ;;

      -C | --no-cleanup)
        PW_OPTION_NO_CLEANUP=true

        shift
        ;;

      -N | --author-name)
        option_value_must_be_specified "$@"
        PW_OPTION_APPLY_AUTHOR_NAME="$2"

        PW_OPTION_RESET_AUTHOR_DISABLE=false

        shift 2
        ;;

      -M | --author-email)
        option_value_must_be_specified "$@"
        PW_OPTION_APPLY_AUTHOR_EMAIL="$2"

        PW_OPTION_RESET_AUTHOR_DISABLE=false

        shift 2
        ;;

      -H | --leave-author)
        PW_OPTION_RESET_AUTHOR_DISABLE=true

        shift
        ;;

      --reset-author)
        PW_OPTION_RESET_AUTHOR_DISABLE=false

        shift
        ;;

      -f | --force)
        PW_OPTION_FORCE_PUSH=true

        shift
        ;;

      -F | --no-force)
        PW_OPTION_FORCE_PUSH=false

        shift
        ;;

      -l | --liminal)
        PW_OPTION_USE_LIMINAL=true

        shift
        ;;

      -L | --no-liminal)
        PW_OPTION_USE_LIMINAL=false

        shift
        ;;

      --explain)
        PW_OPTION_QUICK_TIG=false

        shift
        ;;

      -E | --no-explain)
        PW_OPTION_QUICK_TIG=true

        shift
        ;;

      -y | --yes)
        PW_OPTION_AUTO_CONFIRM=true

        shift
        ;;

      --no-yes)
        PW_OPTION_AUTO_CONFIRM=false

        shift
        ;;

      -u | --squash)
        PW_OPTION_SKIP_SQUASH=false

        shift
        ;;

      -U | --no-squash)
        PW_OPTION_SKIP_SQUASH=true

        shift
        ;;

      -S | --starting-ref)
        option_value_must_be_specified "$@"
        PW_OPTION_STARTING_REF="$2"

        shift 2
        ;;

      -b | --branch)
        option_value_must_be_specified "$@"
        PW_OPTION_BRANCH="$2"

        shift 2
        ;;

      -r | --remote)
        option_value_must_be_specified "$@"
        PW_OPTION_REMOTE="$2"

        shift 2
        ;;

      -g | --regenerate-receipts)
        option_value_must_be_specified "$@"
        PW_OPTION_REGENERATE_RECEIPTS="$2"

        shift 2
        ;;

      -v | --verbose)
        PW_OPTION_VERBOSE=true

        shift
        ;;

      --no-verbose)
        PW_OPTION_VERBOSE=false

        shift
        ;;

      -T | --dry-run)
        # Mnemonic: 'T' for 'test'. (As opposed to -D for --dry-run.)
        PW_OPTION_DRY_RUN=true

        shift
        ;;

      # The "elevenses" feature is only used internally (otherwise it'd
      # be more tellingly named). It's quietly exposed for testing (you
      # won't see it in the --help).
      -11 | --fail-elevenses)
        PW_OPTION_FAIL_ELEVENSES=true

        shift
        ;;

      # If arg. starts with a dash prefix but doesn't match any of the
      # single-dash options above, we'll be somewhat magical like `tar`
      # and other commands that allow user to scrunch options together.
      # - E.g., `put-wise --push --force --verbose` → `put-wise -ofv`
      *)
        local cur_arg="$1"
        if [ "${1#-}" != "${cur_arg}" ]; then
          # First check if starts with two or more dashes, which is an error:
          # - If two dashes, arg didn't match anything previous, so invalid.
          #   - If three or more dashes, obviously not an option, but could
          #     be a path, in which case user must use `--` separator.
          # - If starts with single dash, but only single character given,
          #   then an error because arg didn't match anything previous.
          if [ "${cur_arg#--}" != "$${cur_arg}" ] || [ "${#cur_arg}" -eq 2 ]; then
            >&2 echo "ERROR: Unrecognized argument: “${cur_arg}”."
            >&2 echo "- HINT: Use \`--\` separator if you this argument is the path."

            exit 1
          fi
          # Support scrunching single-char options, e.g., `put-wise -oR`.
          shift
          for char in $(echo "${cur_arg#-}" | sed -E -e 's/(.)/\1\n/g'); do
            case ${char} in
              # h)  # Previously handled
              # V)  # Previously handled
              o)
                PW_ACTION_PUSH=true
                ;;
              i)
                PW_ACTION_PULL=true
                ;;
              e)
                PW_ACTION_ARCHIVE=true
                ;;
              a)
                PW_ACTION_APPLY=true
                ;;
              A)
                PW_ACTION_APPLY_ALL=true
                ;;
              R)
                PW_ACTION_RESET=true
                ;;
              # MAYBE?
              # X)
              #   PW_ACTION_SHA=true
              #   ;;
              J)
                option_value_must_be_specified "-J" "$@"
                PW_PROJECT_PATH="$1"
                project_path_arg_seen=true

                shift
                ;;
              O)
                option_value_must_be_specified "-O" "$@"
                PW_PATCHES_REPO="$1"

                shift
                ;;
              n)
                option_value_must_be_specified "-n" "$@"
                PW_OPTION_PASS_NAME="$1"

                shift
                ;;
              c)
                PW_OPTION_NO_CLEANUP=false
                ;;
              C)
                PW_OPTION_NO_CLEANUP=true
                ;;
              N)
                option_value_must_be_specified "-N" "$@"
                PW_OPTION_APPLY_AUTHOR_NAME="$1"

                PW_OPTION_RESET_AUTHOR_DISABLE=false

                shift
                ;;
              M)
                option_value_must_be_specified "-N" "$@"
                PW_OPTION_APPLY_AUTHOR_EMAIL="$1"

                PW_OPTION_RESET_AUTHOR_DISABLE=false

                shift
                ;;
              H)
                PW_OPTION_RESET_AUTHOR_DISABLE=true
                ;;
              f)
                PW_OPTION_FORCE_PUSH=true
                ;;
              F)
                PW_OPTION_FORCE_PUSH=false
                ;;
              l)
                PW_OPTION_USE_LIMINAL=true
                ;;
              L)
                PW_OPTION_USE_LIMINAL=false
                ;;
              E)
                PW_OPTION_QUICK_TIG=true
                ;;
              y)
                PW_OPTION_AUTO_CONFIRM=true
                ;;
              u)
                PW_OPTION_SKIP_SQUASH=false
                ;;
              U)
                PW_OPTION_SKIP_SQUASH=true
                ;;
              S)
                option_value_must_be_specified "-S" "$@"
                PW_OPTION_STARTING_REF="$1"

                shift
                ;;
              b)
                option_value_must_be_specified "-b" "$@"
                PW_OPTION_BRANCH="$1"

                shift
                ;;
              r)
                option_value_must_be_specified "-r" "$@"
                PW_OPTION_REMOTE="$1"

                shift
                ;;
              g)
                option_value_must_be_specified "-g" "$@"
                PW_OPTION_REGENERATE_RECEIPTS="$1"

                shift
                ;;
              v)
                PW_OPTION_VERBOSE=true
                ;;
              T)
                PW_OPTION_DRY_RUN=true
                ;;
              # No reason user should use elevenses option.
              #  1)
              #    PW_OPTION_FAIL_ELEVENSES=true
              #    ;;
              *)
                >&2 echo "ERROR: Unrecognized argument: “-${char}” (in “$1”)."
                >&2 echo "- HINT: Use \`--\` separator if you meant to specify a path."

                exit 1
                ;;
            esac
          done
        else
          # Else, this is the project path that the user wants to work on.
          must_not_have_set_path_yet ${project_path_arg_seen} "${PW_PROJECT_PATH}" "$1"

          PW_PROJECT_PATH="$1"
          project_path_arg_seen=true
        fi

        shift
        ;;
    esac
  done

  # If `--` detected, the while loop stopped before processing all args,
  # and the final argument is assumed to be the path (and not an option).
  if [ -n "$1" ]; then
    must_not_have_set_path_yet ${project_path_arg_seen} "${PW_PROJECT_PATH}" "$1"

    PW_PROJECT_PATH="$1"
    project_path_arg_seen=true

    shift

    if [ -n "$1" ]; then
      >&2 echo "ERROR: Too many arguments, starting with: “$1”."

      exit 1
    fi
  fi

  return 0
}

option_value_must_be_specified () {
  local option="$1"

  [ ${#@} -lt 2 ] || return 0

  >&2 echo "ERROR: Option “${option}” expects an argument."

  exit 1
}

# ***

must_not_have_set_path_yet () {
  local project_path_arg_seen=$1
  local project_path_first_arg="$2"
  local project_path_extraneous="$3"

  "${project_path_arg_seen}" || return 0

  >&2 echo "ERROR: Please specify only one path."
  >&2 echo "- The first path arg. specified “${project_path_first_arg}”."
  >&2 echo "- The extraneous arg. specifies “${project_path_extraneous}”."

  exit 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# User must specify an action: push|pull|archive|apply|apply-all.

# - FYI, I tried logger.sh `error` here, but loud. `echo` more gentle.
#   - I like to use `error` when there's a lot of log output, and you
#     need to grab the user's attention. Which is not the case here.

cli_must_verify_action_specified () {
  local verified=true

  ( ${PW_ACTION_PUSH} ||
    ${PW_ACTION_PULL} ||
    ${PW_ACTION_ARCHIVE} ||
    ${PW_ACTION_APPLY} ||
    ${PW_ACTION_APPLY_ALL} ||
    ${PW_ACTION_RESET} ||
    ${PW_ACTION_SHA} ||
    ${PW_ACTION_REBASE_CONTINUE} ||
    ${PW_ACTION_REBASE_ABORT} ||
    ${PW_ACTION_PULL_CLEANUP} \
  ) && return 0

  # (lb): I like -v for verbose because -vvv feels like a popular option
  # for apps to have. But if no action supplied, should `./app -v` print
  # expects-a-command "error"? or should it just show the version? both?
  if [ ${#@} -eq 1 ] && [ "$1" = "-v" ]; then
    echo "${PW_VERSION}"
  fi

  >&2 echo "ERROR: Please specify a command. See --help for help."

  exit 1
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# Note that when logger.sh is sourced, it sets LOG_LEVEL=${LOG_LEVEL:-40}.
# - If you use logger.sh for other projects, it's recommended that you
#   *do not* export LOG_LEVEL from your session. E.g., consider:
#
#   $ declare -p LOG_LEVEL
#   declare -- LOG_LEVEL="10"
#
#   $ declare -p PW_PATCHES_REPO
#   declare -x PW_PATCHES_REPO="/home/landonb/.depoxy/patchr"
#
# If you would like to set your own level, use PW_LOG_LEVEL.
#
# - This code leaves PW_LOG_LEVEL unset, so in practice, LOG_LEVEL is
#   generally 40 (WARNING), unless set to 10 (TRACE) because --verbose.

cli_setup_log_level () {
  ${PW_OPTION_VERBOSE} \
    && LOG_LEVEL=${LOG_LEVEL_TRACE} \
    || LOG_LEVEL=${PW_LOG_LEVEL:-${LOG_LEVEL}}
}

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

source_deps

# "Complain" if executed.
if [ "$0" = "${BASH_SOURCE}" ]; then
  >&2 echo "😶"
fi


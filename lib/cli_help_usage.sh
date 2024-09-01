#!/usr/bin/env bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/git-put-wise#🥨
# License: MIT

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PW_USAGE="\
USAGE: git put-wise <command> [<options>...] [--] [<path>]

Commands
========

Specify one:

  General commands
  ----------------

  -h|--help|help            Print this help
  -V|--version              Print the program version

  Single Project commands
  -----------------------

  -o|--push|push            Publish changes to relevant remotes
  -i|--pull|pull            Consume changes from remote branch
  -e|--archive|archive      Create encrypted patch archive
  -y|--apply|apply          Apply patches from encrypted patch archive
                              (where <path> is project path or archive path)

  Other commands
  --------------

  -A|--apply-all            Apply patches from all encrypted archives found
    |apply-all|all            in the patches repo (where --patches-repo is
                              required and <path> is read from each archive)

  -R|--reset                (Re)create the patches repo

  --rebase-boundary         Print rebase boundary (for sort & sign)

  --scope|scope             Print PRIVATE/PROTECTED boundary SHA

  --sha|sha [<path>]        Print <path> SHA (defaults to project directory)

  --continue|continue       Restart the rebasing process after having resolved
                              a merge conflict (Or call \`git rebase --continue\`)
  --abort|abort             Abort the rebase operation and restore state (Use
                              this command and do not call \`git rebase --abort\`)

Project or Archive path
=======================

  <path>                    Optional path to the project to work on
                              (defaults to the current directory);
                            Or path to the patch archive to apply
                              (when used with --apply)

Additional options
==================

  -J|--project-path <path>  Project or archive path to use (this is an alt-
                              ernative to using the final <path> argument,
                              so \`git put-wise -J .\` == \`git put-wise .\`)

  -O|--patches-repo <repo>  Directory path to repo of patch archives (those
                              created on --archive and consumed on --apply*)

  -n|--pass-name            Password Store entry containing passphrase to use
                              with --archive and --apply* (if unspecified you
                              will be prompted twice by GPG for each archive)

  -c|--cleanup              With --apply*, git-rm each processed archive and
                              \`rm -rf\` its unpacked directory [default]
  -C|--no-cleanup           With --apply*, don’t cleanup (leave both)

  -N|--author-name <name>   With --apply, set commit author name to <name>
  -M|--author-email <mail>  With --apply, set commit author email to <mail>
  -L|--leave-author         With --apply, uses author specified in patches
  --reset-author            ^^^, uses local project’s user.name <user.email>
                              [default] (customize with -N/-M, -L disables)

  -f|--force                With --push, uses git push --force-with-lease
  -F|--no-force             With --push, don’t --force-with-lease [default]

  --explain                 With --push, explain how tig prompt works [default]
  -E|--no-explain           With --push, don’t explain how tig prompt works

  -y|--yes                  With --push, skip tig dialog push confirmation
  --no-yes                  With --push, don't skip tig push confirmation

  --skip-rebase             On --push/--archive, skip sort & sign
  --no-skip-rebase          On --push/--archive, don’t --skip-rebase [default]

  --orphan-tags             On --push/--archive, allow rebase that orphans tags
  --no-orphan-tags          On --push/--archive, don’t --orphan-tags [default]

  --ignore-author           On --push/--archive, allow rebase multiple author commits
  --no-ignore-author        On --push/--archive, don’t --ignore-author [default]

  -u|--squash               Fixup commits to the patches repo [default]
  -U|--no-squash            Make new commits to patches repo

  -S|--starting-ref <ref>   On --archive, format-patch <starting gitref>..HEAD
                              but generally for special circumstances

  -b|--branch <name>        Override put-wise branch choice
  -r|--remote <name>        Override put-wise remote choice

  -v|--verbose              Print excess blather
  --no-verbose              Don’t print excess blather
  -T|--dry-run              Print git commands to run but do not make changes
                            - Hint: When combined with --apply-all, dry-run
                              decrypts all patchkages, leaves them unpacked,
                              but does not apply them.

Environment variables you can use instead of options above:

  -o|--push|push            PW_ACTION_PUSH=true|false
  -i|--pull|pull            PW_ACTION_PULL=true|false
  -e|--archive|archive      PW_ACTION_ARCHIVE=true|false
  -y|--apply|apply          PW_ACTION_APPLY=true|false
  -A|--apply-all|...        PW_ACTION_APPLY_ALL=true|false
  -R|--reset                PW_ACTION_RESET=true|false
  --rebase-boundary         PW_ACTION_REBASE_BOUNDARY=true|false
  --scope|scope             PW_ACTION_SCOPE=true|false
  --sha|sha [<path>]        PW_ACTION_SHA=true PW_PROJECT_PATH=\"<path>\"
  --continue|continue       PW_ACTION_REBASE_CONTINUE=true|false
  --abort|abort             PW_ACTION_REBASE_ABORT=true|false

  -J|--project-path <path>  PW_PROJECT_PATH=\"<path>\"
  -O|--patches-repo <repo>  PW_PATCHES_REPO=\"<repo>\"

  -n|--pass-name            PW_OPTION_PASS_NAME=\"<name>\"

  -C|--no-cleanup           PW_OPTION_NO_CLEANUP=true
  -c|--cleanup              PW_OPTION_NO_CLEANUP=false

  -N|--author-name <name>   PW_OPTION_APPLY_AUTHOR_NAME=\"<name>\"
  -M|--author-email <mail>  PW_OPTION_APPLY_AUTHOR_EMAIL=\"<mail>\"
  -a|--leave-author         PW_OPTION_RESET_AUTHOR_DISABLE=true
  --reset-author            PW_OPTION_RESET_AUTHOR_DISABLE=false

  -f|--force/-F|--no-force  PW_OPTION_FORCE_PUSH=true|false
  --explain/-E|--no-explain PW_OPTION_QUICK_TIG=false|true
  --yes/-y|--no-yes         PW_OPTION_AUTO_CONFIRM=true|false

  --skip-rebase/--no-skip-rebase
                            PW_OPTION_SKIP_REBASE=true|false
  --orphan-tags/--no-orphan-tags
                            PW_OPTION_ORPHAN_TAGS=true|false
  --ignore-author/--no-ignore-author
                            PW_OPTION_IGNORE_AUTHOR=true|false

  -U|--no-squash            PW_OPTION_SKIP_SQUASH=true
  -u|--squash               PW_OPTION_SKIP_SQUASH=false

  -S|--starting-ref <ref>   PW_OPTION_STARTING_REF=\"<ref>\"
  -b|--branch <name>        PW_OPTION_BRANCH=\"<name>\"
  -r|--remote <name>        PW_OPTION_REMOTE=\"<name>\"

  -v|--[no-]verbose         PW_OPTION_VERBOSE=true|false
  -T|--dry-run              PW_OPTION_DRY_RUN=true|false
"

# Silent options (that users shouldn't need to worry about):
#
# --about|about             Print an overview of what this program does
#                             [included in README.md and man page]
#
# -11|--fail-elevenses      Exit 11 if action results in no-op
# -11|--fail-elevenses      PW_OPTION_FAIL_ELEVENSES=true|false
#
# -g|--regenerate <gpgf>    With --apply, skip \`git am *.patch\`, and
#                             regenerate return receipt only -- You must
#                             indicate the original encrypted GPG filename
# -g|--regenerate <gpgf>    PW_OPTION_REGENERATE_RECEIPTS=\"<gpgf>\"

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #


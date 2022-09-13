#!/bin/bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/depoxy/depoxy#🍯
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

cat "$(dirname "$0")/parts.01.header.md"

git-put-wise --help |
  awk '
    /^USAGE: git put-wise/ {
      gsub(/</, "\\&lt;", $0);
      gsub(/>/, "\\&gt;", $0);
      sub(/USAGE: git put-wise/, "<git put-wise>", $0);
      print $0;
      parts_file = "'"$(dirname "$0")/parts.02.description.md"'";
      while ((getline < parts_file) > 0) { print; };
      next;
    }
    /^Commands$/ { print "## COMMANDS"; wait_semaphore = 2; }
    /^Project or Archive path$/ { print "## PATH ARG\n\n  Project or Archive path:"; wait_semaphore = 2; }
    /^Additional options$/ { print "## OPTIONS\n\n  Command options:"; wait_semaphore = 2; }
    /^Environment variables you can use in/ { print "## ENVIRONS\n"; }
    { if (wait_semaphore > 0) {
        # To remove title underscore "====="... from --help.
        wait_semaphore -= 1;
      } else if ($0 != "") {
        # Indent line.
        print "  " $0;
      } else {
        # Blank line.
        print;
      }
    }
  '

git-put-wise --about |
  awk '
    BEGIN { waiting = 1; }
    /^About git-put-wise$/ { print "## ABOUT"; wait_semaphore = 2; }
    { if (wait_semaphore > 0) {
        wait_semaphore -= 1;
        waiting = 0;
      } else if (!waiting) {
        print $0;
      }
    }
  '

cat "$(dirname "$0")/parts.03.footer.md"


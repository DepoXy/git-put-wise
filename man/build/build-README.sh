#!/bin/bash
# vim:tw=0:ts=2:sw=2:et:norl:ft=bash
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/DepoXy/depoxy#🍯
# License: MIT

# Copyright (c) © 2022-2023 Landon Bouma. All Rights Reserved.

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

# COPYD: See same-name variable in Makefile.
DOC_PW="man/git-put-wise.1.md"

cat "$(dirname -- "$0")/../../${DOC_PW}" |
  awk '
    BEGIN { done = 0; }
    /^[^[:space:]]/ {
      gsub(/</, "`", $0);
      gsub(/>/, "`", $0);
      gsub(/&lt;`/, "\\&lt;", $0);
      gsub(/`&gt;/, "\\&gt;", $0);
    }
    /^## SEE ALSO$/ { done = 1; }
    !done { print $0; }
  '


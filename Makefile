# vim:tw=0:ts=2:sw=2:et:norl:ft=make
# Author: Landon Bouma <https://tallybark.com/>
# Project: https://github.com/depoxy/git-put-wise#🥨
# License: MIT

# USAGE:
#   PREFIX=~/.local make install

# COPYD: This Makefile modified from a copy of git-extras's:
#   https://github.com/tj/git-extras

# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ #

PREFIX ?= /usr/local
BINPREFIX ?= "$(PREFIX)/bin"
SHELL := bash

OS = $(shell uname)
ifeq ($(OS), FreeBSD)
	MANPREFIX ?= "$(PREFIX)/man/man1"
else
	MANPREFIX ?= "$(PREFIX)/share/man/man1"
endif

ORGANIZATION = $(shell \
		grep -e "^PW_VERSION=" lib/cli_parse_params.sh \
			| sed 's/PW_VERSION="\(.*\)"/\1/'; \
		printf "(DepoXy)"; \
	)

BIN_PW = bin/git-put-wise
DOC_PW = man/git-put-wise.1.md
MAN_PW = man/git-put-wise.1
BINS = $(BIN_PW)
MANS = $(wildcard man/*.md)
MAN_HTML = $(MANS:.1.md=.1.html)
MAN_PAGES = $(MANS:.1.md=.1)

default: install

# Make a second pass of `make docs` to process generated git-put-wise.md.
# - Or at least that's this author's possible naïve solution.
docs: $(DOC_PW) $(MAN_HTML) $(MAN_PAGES)
	@if [ ! -f "$(MAN_PW)" ]; then \
		make docs; \
	fi

install:
	@mkdir -p $(DESTDIR)$(MANPREFIX)
	@mkdir -p $(DESTDIR)$(BINPREFIX)
	@echo "... installing bins to $(DESTDIR)$(BINPREFIX)"
	@ln -sfn "$(realpath $(BIN_PW))" "$(DESTDIR)$(BINPREFIX)/"
	@echo "... installing man pages to $(DESTDIR)$(MANPREFIX)"
	@if [ -z "$(wildcard man/git-*.1)" ]; then \
		echo "WARNING: man pages not created, use 'make docs' (which requires 'ronn' ruby lib)"; \
	else \
		cp -f man/git-*.1 $(DESTDIR)$(MANPREFIX); \
		echo "cp -f man/git-*.1 $(DESTDIR)$(MANPREFIX)"; \
	fi

# Generate git-put-wise.md from --help, --about, and man/build/*.md partials.
$(DOC_PW):
	@./man/build/build-man.sh > $(DOC_PW)
	@./man/build/build-README.sh > README.md

# SAVVY: `ronn` defaults to today's date, which we could also specify,
#   e.g., `--date "2023-02-26"`, but `ronn` nonetheless only prints the
#   month in the man page, e.g., "February 2023".
#   - I looked for a format option but only found syling via CSS;
#     I didn't see a way to generate a more specific date, such as
#     how `man git` shows, e.g., "11/21/2022" in the footer.
man/%.1.html: $(DOC_PW) man/%.1.md
	ronn \
		--manual "Git-Put-Wise" \
		--organization "$(ORGANIZATION)" \
		--html \
		--pipe \
		$< > $@

man/%.1: $(DOC_PW) man/%.1.md
	ronn -r \
		--manual "Git-Put-Wise" \
		--organization "$(ORGANIZATION)" \
		--pipe \
		$< > $@

uninstall:
	@$(foreach BIN, $(BINS), \
		echo "... uninstalling $(DESTDIR)$(BINPREFIX)/$(notdir $(BIN))"; \
		rm -f $(DESTDIR)$(BINPREFIX)/$(notdir $(BIN)); \
	)
	@$(foreach MAN, $(MAN_PAGES), \
		echo "... uninstalling $(DESTDIR)$(MANPREFIX)/$(notdir $(MAN))"; \
		rm -f $(DESTDIR)$(MANPREFIX)/$(notdir $(MAN)); \
	)

clean: docclean

docclean:
	rm -f man/*.1
	rm -f man/*.html
	rm -f $(DOC_PW)
	rm -f README.md

.PHONY: default docs clean docclean install uninstall

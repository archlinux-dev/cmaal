# cmaal Makefile
#
#   make install                      install to /usr/local
#   make install PREFIX=/usr          what the PKGBUILD does
#   make install PREFIX=~/.local      just for you, no root
#   make uninstall PREFIX=...
#   make test                         run the test suite
#   make lint                         shellcheck everything

PREFIX  ?= /usr/local
DESTDIR ?=

VERSION := $(shell tr -d '[:space:]' < VERSION)

BINDIR      = $(PREFIX)/bin
LIBDIR      = $(PREFIX)/lib/cmaal
SHAREDIR    = $(PREFIX)/share/cmaal
DOCDIR      = $(PREFIX)/share/doc/cmaal
LICENSEDIR  = $(PREFIX)/share/licenses/cmaal
MANDIR      = $(PREFIX)/share/man/man1
BASHCOMPDIR = $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR  = $(PREFIX)/share/zsh/site-functions
FISHCOMPDIR = $(PREFIX)/share/fish/vendor_completions.d

SHELL_FILES = bin/cmaal lib/*.sh install.sh tests/run.sh completions/cmaal.bash packaging/aur/publish.sh

.PHONY: all install uninstall test lint check

all:
	@echo "Nothing to build. Run 'make install' (PREFIX=$(PREFIX))."

install:
	install -Dm755 bin/cmaal "$(DESTDIR)$(BINDIR)/cmaal"
	sed -i -e 's|^CMAAL_VERSION=""|CMAAL_VERSION="$(VERSION)"|' \
	       -e 's|^CMAAL_PREFIX=""|CMAAL_PREFIX="$(PREFIX)"|' "$(DESTDIR)$(BINDIR)/cmaal"
	install -dm755 "$(DESTDIR)$(LIBDIR)"
	install -m644 lib/*.sh "$(DESTDIR)$(LIBDIR)/"
	install -Dm644 share/config.default "$(DESTDIR)$(SHAREDIR)/config.default"
	install -Dm644 share/logo.txt "$(DESTDIR)$(SHAREDIR)/logo.txt"
	install -dm755 "$(DESTDIR)$(SHAREDIR)/i18n"
	install -m644 share/i18n/* "$(DESTDIR)$(SHAREDIR)/i18n/"
	# whatsnew reads this at runtime; /usr/share/doc may be NoExtract
	install -Dm644 CHANGELOG.md "$(DESTDIR)$(SHAREDIR)/CHANGELOG.md"
	install -Dm644 man/cmaal.1 "$(DESTDIR)$(MANDIR)/cmaal.1"
	sed -i 's|@VERSION@|$(VERSION)|' "$(DESTDIR)$(MANDIR)/cmaal.1"
	install -Dm644 completions/cmaal.bash "$(DESTDIR)$(BASHCOMPDIR)/cmaal"
	install -Dm644 completions/_cmaal "$(DESTDIR)$(ZSHCOMPDIR)/_cmaal"
	install -Dm644 completions/cmaal.fish "$(DESTDIR)$(FISHCOMPDIR)/cmaal.fish"
	install -Dm644 README.md "$(DESTDIR)$(DOCDIR)/README.md"
	install -Dm644 CHANGELOG.md "$(DESTDIR)$(DOCDIR)/CHANGELOG.md"
	install -Dm644 LICENSE "$(DESTDIR)$(LICENSEDIR)/LICENSE"

uninstall:
	rm -f  "$(DESTDIR)$(BINDIR)/cmaal"
	rm -rf "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(SHAREDIR)" "$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(LICENSEDIR)"
	rm -f  "$(DESTDIR)$(MANDIR)/cmaal.1"
	rm -f  "$(DESTDIR)$(BASHCOMPDIR)/cmaal" "$(DESTDIR)$(ZSHCOMPDIR)/_cmaal" "$(DESTDIR)$(FISHCOMPDIR)/cmaal.fish"

test:
	bash tests/run.sh

lint:
	shellcheck $(SHELL_FILES)
	for f in $(SHELL_FILES); do bash -n "$$f" || exit 1; done

# quick check used by the PKGBUILD: every file parses
check:
	for f in bin/cmaal lib/*.sh; do bash -n "$$f" || exit 1; done

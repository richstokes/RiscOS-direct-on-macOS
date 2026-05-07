SHELL_SCRIPTS := run.sh $(sort $(wildcard scripts/*.sh))
BASH_CMD ?= bash

.PHONY: fetch-riscos4-roms fetch-rpcemu-mac fetch-riscos4-cd prepare-rpcemu-riscos4 rpcemu-riscos4 check-scripts

fetch-riscos4-roms:
	@scripts/fetch-riscos4-roms.sh

fetch-rpcemu-mac:
	@scripts/fetch-rpcemu-mac.sh

fetch-riscos4-cd:
	@scripts/fetch-riscos4-cd.sh

prepare-rpcemu-riscos4:
	@scripts/prepare-rpcemu-riscos4.sh

rpcemu-riscos4:
	@scripts/run-rpcemu-riscos4.sh \
		$(if $(FLOPPY),--floppy "$(FLOPPY)") \
		$(if $(FLOPPY1),--floppy1 "$(FLOPPY1)") \
		$(if $(LINK_FLOPPY),--link-floppy) \
		$(if $(HARD_DRIVE),--hard-drive "$(HARD_DRIVE)") \
		$(if $(HARD_DRIVE5),--hard-drive5 "$(HARD_DRIVE5)") \
		$(if $(COPY_HARD_DRIVE),--copy-hard-drive) \
		$(if $(WINDOW_POSITION),--window-position "$(WINDOW_POSITION)") \
		$(if $(NO_WINDOW_POSITION),--no-window-position)

check-scripts:
	@set -e; \
	for script in $(SHELL_SCRIPTS); do \
		echo "$(BASH_CMD) -n $$script"; \
		"$(BASH_CMD)" -n "$$script"; \
	done

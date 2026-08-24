# Connect IQ watch face — Instinct Crossover AMOLED
#
# The SDK path is resolved at run time rather than hard-coded, so upgrading the
# SDK (connect-iq-sdk-manager sdk set <version>) needs no edit here.

SDK    := $(shell connect-iq-sdk-manager sdk current-path)
DEVICE ?= instinctcrossoveramoled
KEY    ?= $(HOME)/.Garmin/ConnectIQ/developer_key.der
NAME   := CrossoverFace

PRG := bin/$(NAME).prg
IQ  := bin/$(NAME).iq

MONKEYC  := $(SDK)bin/monkeyc
MONKEYDO := $(SDK)bin/monkeydo
SIMULATOR := $(SDK)bin/connectiq

.PHONY: all build test sim simulator-up install package clean sdk-info

all: build

## Debug build for the simulator.
build:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o $(PRG) -y "$(KEY)" -d $(DEVICE) -w

## Unit tests (source annotated with :test).
## monkeydo exits non-zero even when every test passes, so the summary line is
## what decides the result.
test:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o bin/$(NAME)-test.prg -y "$(KEY)" -d $(DEVICE) -w -t
	@$(MAKE) -s simulator-up
	@out=$$("$(MONKEYDO)" bin/$(NAME)-test.prg $(DEVICE) -t 2>&1); \
	echo "$$out"; \
	echo "$$out" | grep -q "^PASSED" || { echo; echo "TESTS FAILED"; exit 1; }

## Start the simulator unless it is already running.
simulator-up:
	@pgrep -f 'ConnectIQ.app/Contents/MacOS/simulator' >/dev/null && exit 0; \
	echo "starting simulator..."; "$(SIMULATOR)"; \
	n=0; until pgrep -f 'ConnectIQ.app/Contents/MacOS/simulator' >/dev/null; do \
		n=$$((n+1)); [ $$n -ge 60 ] && { echo "simulator did not start"; exit 1; }; \
		/bin/sleep 0.5; \
	done; /bin/sleep 3

## Launch the simulator (if not already up) and sideload the face.
## Stays attached to stream println output — Ctrl-C to detach.
sim: build
	@$(MAKE) -s simulator-up
	"$(MONKEYDO)" $(PRG) $(DEVICE)

## Get the built face onto the watch.
## Modern Garmin devices are MTP-only — macOS cannot mount them, so there is
## nothing to cp to. Older mass-storage devices still work directly.
install: build
	@apps=$$(ls -d /Volumes/*/GARMIN/APPS 2>/dev/null | head -1); \
	if [ -n "$$apps" ]; then \
		echo "mass storage detected: $$apps"; \
		cp $(PRG) "$$apps/" && sync; \
		echo "Copied. Eject the volume, then on the watch hold MENU ->"; \
		echo "Watch Face -> Crossover Face"; \
		exit 0; \
	fi; \
	if ! ioreg -p IOUSB -w0 -l 2>/dev/null | grep -q '"idVendor" = 2334'; then \
		echo "No Garmin device on USB. Connect the watch with a data cable."; \
		exit 1; \
	fi; \
	echo "Watch is connected over MTP, which macOS cannot mount."; \
	echo "Opening OpenMTP — drag the revealed file into GARMIN/Apps/"; \
	echo; \
	echo "  $(PRG)"; \
	echo; \
	echo "Then on the watch: hold MENU -> Watch Face -> Crossover Face"; \
	open -a OpenMTP 2>/dev/null || echo "(brew install --cask openmtp)"; \
	open -R $(PRG)

## Signed store package.
package:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o $(IQ) -y "$(KEY)" -e -r -w

clean:
	rm -rf bin

sdk-info:
	@echo "SDK    : $(SDK)"
	@echo "Device : $(DEVICE)"
	@echo "Key    : $(KEY)"
	@"$(MONKEYC)" -v

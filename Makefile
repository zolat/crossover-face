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

PUSH  := tools/mtp_push.py
KALAM := /Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib

## There is one simulator per machine, so parallel sessions have to take turns.
## SIM_LOCK serialises them; see tools/sim_lock.sh for why it is not shlock.
SIM_LOCK := tools/sim_lock.sh

MONKEYC  := $(SDK)bin/monkeyc
MONKEYDO := $(SDK)bin/monkeydo
SIMULATOR := $(SDK)bin/connectiq

.PHONY: all build test test-lock sim simulator-up install push push-built \
        reveal package clean sdk-info

all: build

## Debug build for the simulator.
build:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o $(PRG) -y "$(KEY)" -d $(DEVICE) -w

## Unit tests (source annotated with :test).
## monkeydo exits non-zero even when every test passes, so the summary line is
## what decides the result.
##
## The run holds the simulator lock from before the simulator is started until
## after monkeydo returns. Without it a second session sideloading mid-run takes
## this one down, and a killed run prints a bare "TESTS FAILED" with no output —
## indistinguishable from a real failure. $$$$ is the recipe shell's own PID, so
## a session that dies leaves a lock the next one can see is stale.
test:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o bin/$(NAME)-test.prg -y "$(KEY)" -d $(DEVICE) -w -t
	@$(SIM_LOCK) acquire $$$$ || exit 1; \
	trap '$(SIM_LOCK) release $$$$' EXIT INT TERM; \
	$(MAKE) -s simulator-up; \
	out=$$("$(MONKEYDO)" bin/$(NAME)-test.prg $(DEVICE) -t 2>&1); \
	echo "$$out"; \
	echo "$$out" | grep -q "^PASSED" && exit 0; \
	echo; \
	if echo "$$out" | grep -q "^Ran [0-9]"; then \
		echo "TESTS FAILED"; \
	else \
		echo "TESTS FAILED — but nothing ran, so this is contention, not a"; \
		echo "failing test. Something else took the simulator mid-run. The lock"; \
		echo "only covers make targets, so a hand-rolled monkeydo slips past it."; \
		others=$$(pgrep -fl 'MonkeyDoDeux' || true); \
		[ -n "$$others" ] && { echo "still attached:"; echo "$$others" | sed 's/^/  /'; }; \
		echo "Re-run before believing this."; \
	fi; \
	exit 1

## Prove the lock still behaves. Cheap, and it caught a real bug once.
test-lock:
	@tools/sim_lock_test.sh

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
##
## This holds the lock for as long as it stays attached, which is deliberate.
## The first cut only *waited* for the lock and then let go, on the theory that
## an interrupted look at the face is cheaper than an interrupted test run.
## That has it backwards: an attached monkeydo owns the simulator, so it is the
## test run that gets dropped — and it is dropped silently, with no output at
## all. Whoever is watching the face can see a message and press Ctrl-C; a test
## run cannot. So `sim` keeps the lock and `test` waits its turn.
sim: build
	@$(SIM_LOCK) acquire $$$$ || exit 1; \
	trap '$(SIM_LOCK) release $$$$' EXIT INT TERM; \
	$(MAKE) -s simulator-up; \
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
	if ! ioreg -p IOUSB -w0 -l 2>/dev/null | grep -q '"idProduct" = 21062'; then \
		echo "The watch is on USB but not in MTP mode (needs idProduct 0x5246)."; \
		echo "Unplug it, plug it back in, and answer YES to \"Use MTP?\"."; \
		exit 1; \
	fi; \
	if [ ! -f "$(KALAM)" ]; then \
		echo "OpenMTP is not installed, so there is no MTP engine to drive:"; \
		echo "  brew install --cask openmtp"; \
		exit 1; \
	fi; \
	$(MAKE) -s push-built || { \
		echo; echo "Direct push failed — falling back to the manual drag."; \
		$(MAKE) -s reveal; \
	}

## Push straight to the watch over MTP — no GUI, no drag.
## Drives OpenMTP's own MTP engine (kalam.dylib) through tools/mtp_push.py.
push: build push-built

## The push itself, assuming bin/ is already current. install: calls this
## rather than push: so the face is not compiled twice.
push-built:
	@if pgrep -f 'OpenMTP.app/Contents/MacOS/OpenMTP' >/dev/null; then \
		echo "Quitting OpenMTP — only one process may claim the watch."; \
		osascript -e 'quit app "OpenMTP"' >/dev/null 2>&1; /bin/sleep 2; \
	fi
	@python3 $(PUSH) $(PRG)
	@echo "On the watch: hold MENU -> Watch Face -> Crossover Face"

## The old manual route, kept as the fallback: open OpenMTP and reveal the
## .prg so it can be dragged into GARMIN/Apps by hand.
reveal: build
	@echo "Drag the revealed file into GARMIN/Apps/"; echo; echo "  $(PRG)"; echo
	@open -a OpenMTP 2>/dev/null || echo "(brew install --cask openmtp)"
	@open -R $(PRG)

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

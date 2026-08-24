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

.PHONY: all build test sim package clean sdk-info

all: build

## Debug build for the simulator.
build:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o $(PRG) -y "$(KEY)" -d $(DEVICE) -w

## Unit tests (source annotated with :test).
test:
	@mkdir -p bin
	"$(MONKEYC)" -f monkey.jungle -o bin/$(NAME)-test.prg -y "$(KEY)" -d $(DEVICE) -w -t
	"$(MONKEYDO)" bin/$(NAME)-test.prg $(DEVICE) -t

## Launch the simulator (if not already up) and sideload the face.
sim: build
	@pgrep -qx ConnectIQ || "$(SIMULATOR)"
	@printf 'waiting for simulator'
	@n=0; until "$(MONKEYDO)" $(PRG) $(DEVICE) 2>/dev/null; do \
		n=$$((n+1)); \
		if [ $$n -ge 40 ]; then echo " — simulator never accepted the app"; exit 1; fi; \
		printf '.'; /bin/sleep 0.5; \
	done

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

CFLAGS     ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic
CPPFLAGS   := -Isrc
SANFLAGS   ?= -fsanitize=address,undefined -fno-omit-frame-pointer

SCRYER     ?= scryer-prolog

# make V=1 prints the full commands
ifeq ($(V),1)
Q   :=
say := @:
else
Q   := @
say := @printf '  %-9s %s\n'
endif

BUILD := build
GEN   := $(BUILD)/gen
SRCS  := src/zip.c src/image.c src/main.c
HDRS  := src/zip.h src/image.h
PROLOG := zipc $(wildcard prolog/*.pl)

.PHONY: all test sanitize clean format format-check

all: $(BUILD)/zip $(GEN)/gen.pl $(GEN)/concat.bin

$(BUILD)/codegen: src/codegen.c src/zip.c $(HDRS) | $(BUILD)
	$(say) CC $@
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ src/codegen.c src/zip.c

$(GEN)/gen.pl: $(BUILD)/codegen | $(GEN)
	$(say) CODEGEN $@
	$(Q)$(BUILD)/codegen > $@.tmp
	$(Q)mv $@.tmp $@

$(GEN)/%.bin: test/%.pl $(PROLOG) $(GEN)/gen.pl | $(GEN)
	$(Q)SCRYER=$(SCRYER) ./zipc $< $@

$(GEN)/asm/%.bin: test/%.asm.pl $(PROLOG) $(GEN)/gen.pl | $(GEN)/asm
	$(Q)SCRYER=$(SCRYER) ./zipc -a $< $@

$(BUILD)/zip: $(SRCS) $(HDRS) | $(BUILD)
	$(say) CC $@
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $(SRCS)

$(BUILD)/zip-san: $(SRCS) $(HDRS) | $(BUILD)
	$(say) CC $@
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) $(SANFLAGS) -o $@ $(SRCS)

test: $(BUILD)/zip $(GEN)/gen.pl
	$(say) BATS test
	$(Q)SCRYER=$(SCRYER) bats test

sanitize: $(BUILD)/zip-san $(GEN)/gen.pl
	$(say) BATS "test (zip-san)"
	$(Q)SCRYER=$(SCRYER) ZIP=$(BUILD)/zip-san bats test

$(BUILD) $(GEN) $(GEN)/asm:
	$(Q)mkdir -p $@

clean:
	rm -rf $(BUILD)

format:
	clang-format -i $(wildcard src/*.c) $(wildcard src/*.h)

format-check:
	clang-format --dry-run --Werror $(wildcard src/*.c) $(wildcard src/*.h)

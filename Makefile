CFLAGS     ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic
CPPFLAGS   := -Isrc
SANFLAGS   ?= -fsanitize=address,undefined -fno-omit-frame-pointer

SCRYER     ?= scryer-prolog
PL         = $(SCRYER) -f prolog/compile.pl prolog/assemble.pl prolog/main.pl

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
PROLOG := prolog/compile.pl prolog/assemble.pl prolog/main.pl prolog/dump.pl prolog/encode.pl

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
	$(Q)$(PL) -g "main('$<', '$@')" -g halt < /dev/null

$(GEN)/asm/%.bin: test/%.asm.pl $(PROLOG) $(GEN)/gen.pl | $(GEN)/asm
	$(Q)$(PL) -g "assemble('$<', '$@')" -g halt < /dev/null

$(BUILD)/zip: $(SRCS) $(HDRS) | $(BUILD)
	$(say) CC $@
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $(SRCS)

$(BUILD)/zip-san: $(SRCS) $(HDRS) | $(BUILD)
	$(say) CC $@
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) $(SANFLAGS) -o $@ $(SRCS)

test: $(BUILD)/zip $(GEN)/concat.bin $(GEN)/asm/concat.bin
	$(say) CMP "$(GEN)/concat.bin $(GEN)/asm/concat.bin"
	$(Q)cmp $(GEN)/concat.bin $(GEN)/asm/concat.bin
	$(say) RUN $(GEN)/concat.bin
	$(Q)$(BUILD)/zip $(GEN)/concat.bin | diff -u test/concat.expected -

sanitize: $(BUILD)/zip-san $(GEN)/concat.bin
	$(say) RUN-SAN $(GEN)/concat.bin
	$(Q)$(BUILD)/zip-san $(GEN)/concat.bin | diff -u test/concat.expected -

$(BUILD) $(GEN) $(GEN)/asm:
	$(Q)mkdir -p $@

clean:
	rm -rf $(BUILD)

format:
	clang-format -i $(wildcard src/*.c) $(wildcard src/*.h)

format-check:
	clang-format --dry-run --Werror $(wildcard src/*.c) $(wildcard src/*.h)

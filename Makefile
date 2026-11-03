CFLAGS     ?= -std=c11 -O2 -g -Wall -Wextra -Wpedantic
CPPFLAGS   := -Isrc
SANFLAGS   ?= -fsanitize=address,undefined -fno-omit-frame-pointer

SCRYER     ?= scryer-prolog

BUILD := build
GEN   := $(BUILD)/gen
SRCS  := src/zip.c src/image.c src/main.c
HDRS  := src/zip.h src/image.h
PROLOG := prolog/compile.pl prolog/assemble.pl prolog/main.pl prolog/dump.pl prolog/encode.pl

.PHONY: all test sanitize clean format format-check

all: $(BUILD)/zip $(GEN)/gen.pl $(GEN)/concat.bin

$(BUILD)/codegen: src/codegen.c src/zip.c $(HDRS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ src/codegen.c src/zip.c

$(GEN)/gen.pl: $(BUILD)/codegen | $(GEN)
	$(BUILD)/codegen > $@.tmp
	mv $@.tmp $@

$(GEN)/%.bin: test/%.pl zipc $(PROLOG) $(GEN)/gen.pl | $(GEN)
	SCRYER=$(SCRYER) ./zipc $< $@

$(GEN)/asm/%.bin: test/%.asm.pl zipc $(PROLOG) $(GEN)/gen.pl | $(GEN)/asm
	SCRYER=$(SCRYER) ./zipc -a $< $@

$(BUILD)/zip: $(SRCS) $(HDRS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $(SRCS)

$(BUILD)/zip-san: $(SRCS) $(HDRS) | $(BUILD)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SANFLAGS) -o $@ $(SRCS)

test: $(BUILD)/zip $(GEN)/concat.bin $(GEN)/asm/concat.bin
	cmp $(GEN)/concat.bin $(GEN)/asm/concat.bin
	$(BUILD)/zip $(GEN)/concat.bin | diff -u test/concat.expected -

sanitize: $(BUILD)/zip-san $(GEN)/concat.bin
	$(BUILD)/zip-san $(GEN)/concat.bin | diff -u test/concat.expected -

$(BUILD) $(GEN) $(GEN)/asm:
	mkdir -p $@

clean:
	rm -rf $(BUILD)

format:
	clang-format -i $(wildcard src/*.c) $(wildcard src/*.h)

format-check:
	clang-format --dry-run --Werror $(wildcard src/*.c) $(wildcard src/*.h)

WINCC ?= x86_64-w64-mingw32-gcc
DLLTOOL ?= x86_64-w64-mingw32-dlltool
HOSTCC ?= cc
WINCFLAGS ?= -std=c11 -O2 -Wall -Wextra -Werror -Wconversion -Wshadow -fno-ident -ffreestanding
WINLDFLAGS ?= -nostdlib -mwindows -s -Wl,--entry,launcher_entry,--no-insert-timestamp
HOSTCFLAGS ?= -std=c11 -O2 -Wall -Wextra -Werror -Wconversion -Wshadow
HOSTLDFLAGS ?= -static

.PHONY: all clean test package
all: build/HeavenBurnsRed.exe build/hbr-metadata

build:
	mkdir -p $@

build/libhbr-kernel32.a: src/kernel32.def | build
	$(DLLTOOL) -m i386:x86-64 -d $< -l $@

build/HeavenBurnsRed.exe: src/launcher.c build/libhbr-kernel32.a
	$(WINCC) $(WINCFLAGS) $< $(WINLDFLAGS) build/libhbr-kernel32.a -o $@

build/hbr-metadata: src/metadata.c | build
	$(HOSTCC) $(HOSTCFLAGS) $< $(HOSTLDFLAGS) -o $@

build/test-fixtures: tests/fixtures.c | build
	$(HOSTCC) $(HOSTCFLAGS) $< -o $@

test: all build/test-fixtures
	bash tests/run.sh

package: all
	bash scripts/package.sh

clean:
	rm -rf build dist

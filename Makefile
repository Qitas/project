.PHONY: vendor

JOBS = 4
MAKE = make -j $(JOBS)
SCONS = scons -Q -j $(JOBS)

BUILD_DIR             = build
BOARDLOADER_BUILD_DIR = $(BUILD_DIR)/boardloader
BOOTLOADER_BUILD_DIR  = $(BUILD_DIR)/bootloader
PRODTEST_BUILD_DIR    = $(BUILD_DIR)/prodtest
REFLASH_BUILD_DIR     = $(BUILD_DIR)/reflash
FIRMWARE_BUILD_DIR    = $(BUILD_DIR)/firmware
UNIX_BUILD_DIR        = $(BUILD_DIR)/unix

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
UNIX_PORT_OPTS ?= TREZOR_X86=0
else
UNIX_PORT_OPTS ?= TREZOR_X86=1
endif
CROSS_PORT_OPTS ?=

ifeq ($(DISPLAY_ILI9341V), 1)
CFLAGS += -DDISPLAY_ILI9341V=1
CFLAGS += -DDISPLAY_ST7789V=0
endif

PRODUCTION ?= 0

STLINK_VER ?= v2-1
OPENOCD = openocd -f interface/stlink-$(STLINK_VER).cfg -c "transport select hla_swd" -f target/stm32f4x.cfg

BOARDLOADER_START   = 0x08000000
BOOTLOADER_START    = 0x08020000
FIRMWARE_START      = 0x08040000
PRODTEST_START      = 0x08040000

BOARDLOADER_MAXSIZE = 49152
BOOTLOADER_MAXSIZE  = 131072
FIRMWARE_MAXSIZE    = 786432

GITREV=$(shell git describe --always --dirty)
CFLAGS += -DGITREV=$(GITREV)

## help commands:

help: ## show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "\033[36m  make %-20s\033[0m %s\n", $$1, $$2} /^##(.*)/ {printf "\033[33m%s\n", substr($$0, 4)}' $(MAKEFILE_LIST)

install: ## install environment
	sudo dpkg --add-architecture i386;
	sudo apt update;
	sudo apt install scons libsdl2-dev:i386 libsdl2-image-dev:i386 gcc-multilib;
	sudo apt install openocd;
	sudo pip3 install --no-cache-dir click pyblake2 scons;
	sudo pip3 install --no-deps git+https://github.com/trezor/python-trezor.git@master;
	sudo apt install gcc-arm-none-eabi libnewlib-arm-none-eabi;

## dependencies commands:

vendor: ## update git submodules
	git submodule update --init --recursive --force

res: ## update resources
	./tools/res_collect

genkeys: ## generate all keys
	cd sign ;./genkeys; $(warning make sure after this step,you copy keys to the right file)
	
conv: ## convert toif to bin header
	cd sign ;./oazonFirmware;./oazonProdtest

signboot: ## sign the bootloader bin with ed25519 keypairs
	cd sign ;./signbootloader
	
signfw: ## sign the firmware bin with ed25519 keypairs
	cd sign ;./signfirmware
	
signall: ## sign all bin file with ed25519 keypairs
	cd sign ;./signbootloader;./signfirmware

stm32:conv build_boardloader build_bootloader build_firmware signed flash ## build for hardware

## emulator commands:

run: ## run unix port
	cd src ; ../$(UNIX_BUILD_DIR)/micropython

emu: ## run emulator
	./emu.sh

## test commands:

test: ## run unit tests
	cd tests ; ./run_tests.sh $(TESTOPTS)

test_emu: ## run selected device tests from python-trezor
	cd tests ; ./run_tests_device_emu.sh $(TESTOPTS)

pylint: ## run pylint on application sources and tests
	pylint -E $(shell find src -name *.py)
	pylint -E $(shell find tests -name *.py)

style: ## run code style check on application sources and tests
	flake8 $(shell find src -name *.py)
	flake8 $(shell find tests -name *.py)

## build commands:

build: build_boardloader build_bootloader build_firmware build_prodtest build_unix ## build all

build_boardloader: ## build boardloader
	$(SCONS) CFLAGS="$(CFLAGS)" PRODUCTION="$(PRODUCTION)" $(BOARDLOADER_BUILD_DIR)/boardloader.bin

build_bootloader: ## build bootloader
	$(SCONS) CFLAGS="$(CFLAGS)" PRODUCTION="$(PRODUCTION)" $(BOOTLOADER_BUILD_DIR)/bootloader.bin

build_prodtest: ## build production test firmware
	$(SCONS) CFLAGS="$(CFLAGS)" PRODUCTION="$(PRODUCTION)" $(PRODTEST_BUILD_DIR)/prodtest.bin

build_reflash: ## build reflash firmware + reflash image
	$(SCONS) CFLAGS="$(CFLAGS)" PRODUCTION="$(PRODUCTION)" $(REFLASH_BUILD_DIR)/reflash.bin
	dd if=build/boardloader/boardloader.bin of=$(REFLASH_BUILD_DIR)/sdimage.bin bs=1 seek=0
	dd if=build/bootloader/bootloader.bin of=$(REFLASH_BUILD_DIR)/sdimage.bin bs=1 seek=49152

build_firmware: res build_cross ## build firmware with frozen modules
	$(SCONS) CFLAGS="$(CFLAGS)" PRODUCTION="$(PRODUCTION)" $(FIRMWARE_BUILD_DIR)/firmware.bin

build_unix: res ## build unix port
	$(SCONS) CFLAGS="$(CFLAGS)" $(UNIX_BUILD_DIR)/micropython $(UNIX_PORT_OPTS)

build_unix_noui: res ## build unix port without UI support
	$(SCONS) CFLAGS="$(CFLAGS)" $(UNIX_BUILD_DIR)/micropython $(UNIX_PORT_OPTS) TREZOR_NOUI=1

build_cross: ## build mpy-cross port
	$(MAKE) -C vendor/micropython/mpy-cross $(CROSS_PORT_OPTS)

## clean commands:

clean: clean_boardloader clean_bootloader clean_prodtest clean_firmware clean_unix clean_cross ## clean all

clean_boardloader: ## clean boardloader build
	rm -rf $(BOARDLOADER_BUILD_DIR)

clean_bootloader: ## clean bootloader build
	rm -rf $(BOOTLOADER_BUILD_DIR)

clean_prodtest: ## clean prodtest build
	rm -rf $(PRODTEST_BUILD_DIR)

clean_reflash: ## clean reflash build
	rm -rf $(REFLASH_BUILD_DIR)

clean_firmware: ## clean firmware build
	rm -rf $(FIRMWARE_BUILD_DIR)

clean_unix: ## clean unix build
	rm -rf $(UNIX_BUILD_DIR)

clean_cross: ## clean mpy-cross build
	$(MAKE) -C vendor/micropython/mpy-cross clean $(CROSS_PORT_OPTS)

## flash commands:

flash: flash_boardloader flash_bootloader flash_firmware ## flash everything using OpenOCD

flash_boardloader: $(BOARDLOADER_BUILD_DIR)/boardloader.bin ## flash boardloader using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< $(BOARDLOADER_START); exit"

flash_bootloader: $(BOOTLOADER_BUILD_DIR)/bootloader.bin ## flash bootloader using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< $(BOOTLOADER_START); exit"

flash_prodtest: $(PRODTEST_BUILD_DIR)/prodtest.bin ## flash prodtest using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< $(FIRMWARE_START); exit"

flash_firmware: $(FIRMWARE_BUILD_DIR)/firmware.bin ## flash firmware using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< $(FIRMWARE_START); exit"

flash_combine: $(PRODTEST_BUILD_DIR)/combined.bin ## flash combined using OpenOCD
	$(OPENOCD) -c "init; reset halt; flash write_image erase $< $(BOARDLOADER_START); exit"

flash_erase: ## erase all sectors in flash bank 0
	$(OPENOCD) -c "init; reset halt; flash info 0; flash erase_sector 0 0 last; flash erase_check 0; exit"

## openocd debug commands:

openocd: ## start openocd which connects to the device
	$(OPENOCD)

openocd_reset: ## cause a system reset using OpenOCD
	$(OPENOCD) -c "init; reset; exit"

GDB = arm-none-eabi-gdb --nx -ex 'set remotetimeout unlimited' -ex 'set confirm off' -ex 'target remote 127.0.0.1:3333' -ex 'monitor reset halt'

gdb_boardloader: $(BOARDLOADER_BUILD_DIR)/boardloader.elf ## start remote gdb session to openocd with boardloader symbols
	$(GDB) $<

gdb_bootloader: $(BOOTLOADER_BUILD_DIR)/bootloader.elf ## start remote gdb session to openocd with bootloader symbols
	$(GDB) $<

gdb_prodtest: $(PRODTEST_BUILD_DIR)/prodtest.elf ## start remote gdb session to openocd with prodtest symbols
	$(GDB) $<

gdb_firmware: $(FIRMWARE_BUILD_DIR)/firmware.elf ## start remote gdb session to openocd with firmware symbols
	$(GDB) $<

## misc commands:

binctl: ## print info about binary files
	./tools/binctl $(BOOTLOADER_BUILD_DIR)/bootloader.bin
	./tools/binctl $(FIRMWARE_BUILD_DIR)/firmware.bin

bloaty: ## run bloaty size profiler
	bloaty -d symbols -n 0 -s file $(FIRMWARE_BUILD_DIR)/firmware.elf | less
	bloaty -d compileunits -n 0 -s file $(FIRMWARE_BUILD_DIR)/firmware.elf | less

sizecheck: ## check sizes of binary files
	test $(BOARDLOADER_MAXSIZE) -ge $(shell wc -c < $(BOARDLOADER_BUILD_DIR)/boardloader.bin)
	test $(BOOTLOADER_MAXSIZE) -ge $(shell wc -c < $(BOOTLOADER_BUILD_DIR)/bootloader.bin)
	test $(FIRMWARE_MAXSIZE) -ge $(shell wc -c < $(FIRMWARE_BUILD_DIR)/firmware.bin)

combine: ## combine boardloader + bootloader + prodtest into one combined image
	./tools/combine_firmware \
		$(BOARDLOADER_START) $(BOARDLOADER_BUILD_DIR)/boardloader.bin \
		$(BOOTLOADER_START) $(BOOTLOADER_BUILD_DIR)/bootloader.bin \
		$(PRODTEST_START) $(PRODTEST_BUILD_DIR)/prodtest.bin \
		> $(PRODTEST_BUILD_DIR)/combined.bin \

upload: ## upload firmware using trezorctl
	trezorctl firmware_update -f $(FIRMWARE_BUILD_DIR)/firmware.bin

upload_prodtest: ## upload prodtest using trezorctl
	trezorctl firmware_update -f $(PRODTEST_BUILD_DIR)/prodtest.bin
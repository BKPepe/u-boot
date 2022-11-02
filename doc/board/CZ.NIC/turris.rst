.. SPDX-License-Identifier: GPL-2.0+

CZ.NIC Turris routers
=====================

CZ.NIC develops open source Turris routers: Turris 1.0, Turris 1.1, Turris Omnia, and Turris Mox. This document describes a U-Boot deployment (compilation, flashing, resetting) on these routers.

Turris 1.x
----------

Turris 1.0 and Turris 1.1 boards contain Freescale P2020 CPUs with two PowerPC e500v2 cores, which BootROM (or CPU directly) can load and boot U-Boot bootloader from various locations. For Turris 1.x boards, only Flash NOR and SD cards are supported. P2020 CPU cannot download the bootloader via UART like other platforms. For loading the U-Boot bootloader from Flash NOR (which is the default), it is necessary to put SW1 dip switches on the board to position 11001010, and for the SD card to position 01101010 respectively. Note that this controls the source from which P2020 loads U-Boot, not from which U-Boot loads boot script or kernel. Boot procedures from SD card and Flash NOR are different, hence U-Boot binaries need to be compiled differently.

More information about Turris 1.x, including the complete HW documentation (together with the SW1 dip switch options) and Altium design files, can be found at https://docs.turris.cz/hw/turris-1x/turris-1x/

Compilation
^^^^^^^^^^^

To compile the Flash NOR version, run::

    $ make CROSS_COMPILE=powerpc-linux-gnuspe- turris_1x_nor_defconfig
    $ make CROSS_COMPILE=powerpc-linux-gnuspe- u-boot-with-dtb.bin

It will produce a flashable binary file ``u-boot-with-dtb.bin``.

To compile the SD card version, run::

    $ make CROSS_COMPILE=powerpc-linux-gnuspe- turris_1x_sdcard_defconfig
    $ make CROSS_COMPILE=powerpc-linux-gnuspe- u-boot-with-spl.bin

It will produce a bootable binary file ``u-boot-with-spl.bin``.

Flashing
^^^^^^^^

To flash the new U-Boot version into Flash NOR, load binary ``u-boot-with-dtb.bin`` (which must have exact size 0xc0000 bytes) to the ``$loadaddr`` address and run U-Boot commands::

    => protect off 0xeff40000 +0xc0000
    => erase 0xeff40000 +0xc0000
    => cp.b $loadaddr 0xeff40000 0xc0000
    => protect on 0xeff40000 +0xc0000

To load the new U-Boot version to the SD card, just copy the ``u-boot-with-spl.bin`` binary image to sector 0 on the SD card. To preserve existing MBR partitions on the SD card, do not overwrite bytes 440-511 on sector 0. Do it, for example, via the ``dd`` command on Linux::

    $ dd if=u-boot-with-spl.bin of=/dev/mmcblk0 bs=440 count=1
    $ dd if=u-boot-with-spl.bin of=/dev/mmcblk0 bs=512 skip=1

Boot source
^^^^^^^^^^^

By default P2020 CPU boots the U-Boot bootloader from the location configured by SW1 dip switches on Turris 1.x boards. But this configuration can be temporarily overridden by GPIOs (software configured) until the power supply is disconnected or the HW reset button is pressed. U-Boot environment provides commands ``run reboot_to_nor``, ``run reboot_to_sd`` and ``run reboot_to_def`` to force boot source location to Flash NOR, SD card, or default value (configured by SW1 dip switches) and initiate reboot (CPU reset). Overridden configuration is not lost after CPU reset.

This can be useful to temporarily boot U-Boot from a different location (e.g., after flashing the new version) without the need to open the device and change the configuration of SW1 dip switches.

Reset button
^^^^^^^^^^^^

When the HW reset button is pushed, then CPLD puts the main P2020 CPU into a reset state, and the power led starts to blink in a one-second period. After 6 seconds, the power led stays powered on. After the HW reset button is released, CPLD releases the main P2020 CPU from the reset state and U-Boot starts booting on the main P2020 CPU. During startup, U-Boot sets the environment ``$turris_reset`` variable to the duration of the reset button being held in seconds, meaning the count of how many times the power led has blinked. The maximal value is, therefore 6 seconds.

If the HW reset button was held for 6 or more seconds, then U-Boot sets ``$boot_targets`` to ``rescue`` which automatically starts booting the rescue system from Flash NOR, as defined in the ``$bootcmd_rescue`` variable. Note that U-Boot resets default values of these variables to ensure that booting into rescue mode would work correctly also when the custom U-Boot environment stored in permanent Flash NOR storage is damaged or overwritten.

Environment variable ``$turris_reset`` can be used by boot scripts during the boot process for various purposes, like different boot modes.

Turris Omnia
------------

Turris Omnia boards contain Marvell Armada 385 CPU with two ARM Cortex-A9 cores on which BootROM can load U-Boot bootloader from various locations. For Turris Omnia, only SPI NOR and UART are supported. The binary image is the same for both SPI NOR and UART. For UART downloading and booting, a ``kwboot`` application is used (part of U-Boot).

More information about Turris Omnia can be found at: https://docs.turris.cz/hw/omnia/omnia/

Compilation
^^^^^^^^^^^

To compile U-Boot for Turris Omnia, run::

    $ make CROSS_COMPILE=arm-linux-gnueabi- turris_omnia_defconfig
    $ make CROSS_COMPILE=arm-linux-gnueabi- u-boot-spl.kwb

Flashing
^^^^^^^^

To flash the new U-Boot version into SPI NOR, load binary ``u-boot-spl.kwb`` to the ``$loadaddr`` address of size ``$filesize`` and run U-Boot commands::

    => sf probe
    => sf update $loadaddr 0x0 $filesize

UART booting
^^^^^^^^^^^^

Run the ``kwboot`` command with the correct tty device::

    $ ./tools/kwboot -b ./u-boot-spl.kwb -t /dev/ttyUSB0

After that, press the HW reset button on Omnia. ``kwboot`` should instruct Armada 385 CPU BootROM to enter into UART download mode, and transfer ``u-boot-spl.kwb`` binary over UART and boot it.

Armada 385 UART supports speeds up to 5200000 bauds. With appropriate USB-UART converters which support higher speeds, it is possible to speed up transfer via the ``-B`` option. For example ``-B 5200000``.

Reset button
^^^^^^^^^^^^

Like Turris 1.x boards, Turris Omnia also has a dedicated HW reset button. U-Boot during startup sets environment variable ``$omnia_reset`` to the reset mode selected by holding the reset button.

If the HW reset button was held for about a second or more, then U-Boot starts booting the rescue system from SPI NOR. Value from the ``$omnia_reset`` variable is put into the kernel command line, so the rescue system can choose different actions based on reset mode.

mSATA slot configuration
^^^^^^^^^^^^^^^^^^^^^^^^

mSATA slot on Turris Omnia supports both SATA and PCIe modes. By default, it is in auto mode, which means that mode is detected based on the connected mSATA/mPCIe card's pin 43. mPCIe cards must have pin 43 connected to the ground and mSATA cards have this pin disconnected. There are some broken mPCIe cards that do not have grounded this pin and therefore autodetection does not work: the slot is switched to SATA mode and the mPCIe card does not work.

To workaround this issue with buggy mPCIe cards in the mSATA slot, U-Boot provides a way to turn off autodetection and forces mode to PCIe (or also to SATA). U-Boot SPL, during its init phase reads environment variable ``$omnia_msata_slot`` and when it is set to ``sata`` or ``pcie``, then it forces the specified slot mode. In all other cases, it configures mode based on the card's pin 43.

To force mSATA slot mode to PCIe run commands::

    => setenv omnia_msata_slot pcie
    => saveenv
    => reset

To revert mSATA slot mode back to autodetect mode::

    => setenv omnia_msata_slot
    => saveenv
    => reset

WWAN slot configuration
^^^^^^^^^^^^^^^^^^^^^^^

WWAN mPCIe slot (that one with SIM slot) on Turris Omnia is compliant with PCIe Mini CEM 2.1 specification and supports both PCIe and USB 3.0 modes together with USB 2.0 mode.

As defined in PCIe CEM 2.1 specification, PCIe and USB 3.0 functions share the same mPCIe slot pins (23, 25, 31, 33), and therefore only one of these two functions can be activated and configured at the same time. USB 2.0 function is on dedicated mPCIe slot pins. By default, the WWAN slot is in PCIe + USB 2.0 mode. U-Boot SPL during its init phase, reads environment variable ``$omnia_wwan_slot`` and when it is set to ``usb3`` it changes the slot mode (slot pins 23, 25, 31, 33) to USB 3.0.

To set WWAN slot mode to USB 3.0 run the commands::

    => setenv omnia_wwan_slot usb3
    => saveenv
    => reset

To revert WWAN slot back to PCIe + USB 2.0 mode::

    => setenv omnia_wwan_slot
    => saveenv
    => reset

Turris Mox
----------

Turris Mox is a modular router system. Its main Mox-A module contains Marvell Armada 3720 CPU with two 64-bit ARM Cortex-A53 cores and one 32-bit ARM Cortex-M3 on which BootROM can load U-Boot bootloader from various locations. Turris Mox supports only SPI NOR and UART. For UART downloading and booting, a ``mox-imager`` application is used. The firmware itself consists of two parts: Secure firmware, which runs on 32-bit ARM Cortex-M3 core and A53 firmware, which is runs on 64-bit ARM Cortex-A53 cores.

Application ``mox-imager`` is available at: https://gitlab.nic.cz/turris/mox-imager

More information about Turris Mox can be found at: https://docs.turris.cz/hw/mox/intro/

Compilation
^^^^^^^^^^^

To compile U-Boot for Turris Mox, run on a Linux computer::

    $ make CROSS_COMPILE=aarch64-linux-gnu- turris_mox_defconfig
    $ make CROSS_COMPILE=aarch64-linux-gnu- u-boot.bin

Note that a standalone U-Boot cannot be flashed directly into SPI NOR. It can be replaced only as part of the whole A53 firmware which contains a concatenation of a Trusted-Firmware-A BL1 binary and a Trusted-Firmware-A FIT binary. Trusted-Firmware-A FIT binary contains Trusted-Firmware-A BL2 and BL3.1 binaries and also the U-Boot binary.

To compile the final A53 firmware binary, compile the Trusted-Firmware-A project, specifying the path to the u-boot.bin binary in the ``BL33=`` option by commands::

    $ make CROSS_COMPILE=aarch64-linux-gnu- PLAT=a3700 CM3_SYSTEM_RESET=1 USE_COHERENT_MEM=0 FIP_ALIGN=0x100 BL33=u-boot.bin mrvl_bootimage
    $ cp -a build/a3700/release/boot-image.bin a53-firmware.bin
    $ od -v -tu8 -An -j 131184 -N 8 a53-firmware.bin | LC_ALL=C awk '{ for (i = 0; i < 64; i += 8) printf "%c", and(rshift(1441792-131072-$$1, i), 255) }' | dd of=a53-firmware.bin bs=1 seek=131192 count=8 conv=notrunc 2>/dev/null

It will produce a ``a53-firmware.bin`` binary.

The trusted-Firmware-A project is available at: https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git/

Flashing
^^^^^^^^

To flash new A53 firmware binary (which also contains U-Boot) into SPI NOR, load binary ``a53-firmware.bin`` to the ``$loadaddr`` address of size ``$filesize`` and run U-Boot commands::

    => sf probe
    => sf update $loadaddr 0x20000 $filesize

Secure firmware
^^^^^^^^^^^^^^^

Secure firmware is running on Armada 3720 ARM CM3 core, separated from main ARM A53 cores (on which U-Boot and Linux kernel are running).

Due to security reasons, it is not possible to flash one's own version of Secure firmware because it is signed and Armada 3720 CPU checks that signature is done by CZ.NIC signing key. Armada 3720 CPU refuses to boot binary which is not signed by CZ.NIC private key.
Released signed binaries of Secure firmware can be downloaded from CZ.NIC releases webpage: https://gitlab.nic.cz/turris/mox-boot-builder/-/releases
Secure firmware is open source and all sources can be downloaded from CZ.NIC repository webpage: https://gitlab.nic.cz/turris/mox-boot-builder/-/tree/master/wtmi

To flash a new Secure firmware binary (which is signed by the CZ.NIC key) into SPI NOR, load the ``secure-firmware.bin`` binary to the ``$loadaddr`` address of the ``$filesize`` size and run U-Boot commands::

    => sf probe
    => sf update $loadaddr 0x0 $filesize

UART booting
^^^^^^^^^^^^

Run command ``mox-imager`` with correct tty device::

    $ mox-imager -D /dev/ttyUSB0 -E -t secure-firmware-uart.bin a53-firmware.bin

And plug the power supply. If it fails, unplug the power supply and plug it in again.

Armada 3720 UART supports speeds up to 6000000 bauds. With appropriate USB-UART converters which support higher speeds, it is possible to speed up transfer via the ``-b`` option. For example ``-b 6000000``.

Rescue mode
-----------

On All Turris boards, it is possible to boot the rescue system from U-Boot just by calling ``run bootcmd_rescue``. It is the same as pressing the HW reset button for a longer time.

OTP (One Time Programming)
--------------------------

Every Turris board contains some OTP storage that is burned during factory programming and which cannot be later modified or erased. It contains information for device identification: the serial number, mac addresses, etc.

Every Turris 1.0, 1.1, and Omnia board has allocated 3 MAC addresses from CZ.NIC OUI (D8:58:D7) and every Turris Mox board have allocated 2 MAC addresses from CZ.NIC OUI (D8:58:D7). But only the first address is stored in OTP, other MAC addresses can be calculated by numeric `plus one` and `plus two` operations.

Atsha 204/204a OTP content
^^^^^^^^^^^^^^^^^^^^^^^^^^

All Turris 1.0, Turris 1.1 and Turris Omnia boards store into Atsha 204/204a cryptochip OTP area at 32-bit words 0x00-0x03 following data::

    word 0x00 - first half of 64-bit device serial number
      [07:00] - first byte of hw-rev/version (MSB)
      [15:08] - second byte of hw-rev/version
      [23:16] - third byte of hw-rev/version
      [31:24] - fourth byte of hw-rev/version (LSB)

    word 0x01 - second half of 64-bit device serial number
      [07:00] - first byte of serial (MSB)
      [15:08] - second byte of serial
      [23:16] - third byte of serial
      [31:24] - fourth byte of serial (LSB)

    word 0x02 - first half of 48-bit first MAC address with CZ.NIC OUI (D8:58:D7)
      [07:00] - reserved (zero)
      [15:08] - first byte - 0xD8
      [23:16] - second byte - 0x58
      [31:24] - third byte - 0xD7

    word 0x03 - second half of 48-bit first MAC address
      [07:00] - reserved (zero)
      [15:08] - fourth byte
      [23:16] - fifth byte
      [31:24] - sixth byte

Words 0x00 and 0x01 contain 64-bit device serial numbers in a big-endian format, and words 0x02 and 0x03 contain 48-bit first MAC addresses with CZ.NIC OUI (D8:58:D7) in a big-endian format.

Armada 385 LD1 eFuse content
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Turris Omnia boards of revision 32 or higher store into 256-bit long Armada 385 LD1 eFuse OTP following data::

    [047:000] - 48-bit first MAC address with CZ.NIC OUI (D8:58:D7) in big endian
      [007:000] - first byte - 0xD8
      [015:008] - second byte - 0x58
      [023:016] - third byte - 0xD7
      [031:024] - fourth byte
      [039:032] - fifth byte
      [047:040] - sixth byte
    [055:048] - board version
    [063:056] - reserved (zeros)
    [127:064] - 64-bit device serial number in big endian
      [071:064] - first byte of hw-rev/version (MSB)
      [079:072] - second byte of hw-rev/version
      [087:080] - third byte of hw-rev/version
      [095:088] - fourth byte of hw-rev/version (LSB)
      [103:096] - first byte of serial (MSB)
      [111:104] - second byte of serial
      [119:112] - third byte of serial
      [127:120] - fourth byte of serial (LSB)
    [255:128] - reserved (zeros)
    [256]     - lock bit (1 - if above data are valid)

Armada 385 LD1 eFuse is mapped to U-Boot fuse bank number 65.

Read serial number::

    => fuse read 65 2 1

Armada 3720 Secure OTP content
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

All Turris Mox boards store into Armada 3720 Secure OTP 64-bit rows 42 and 43 following data::

    row 42
      [47:00] - 48-bit first MAC address with CZ.NIC OUI (D8:58:D7) in little endian
        [07:00] - sixth byte
        [15:08] - fifth byte
        [23:16] - fourth byte
        [31:24] - third byte - 0xD7
        [39:32] - second byte - 0x58
        [47:40] - first byte - 0xD8
      [53:48] - board version
      [55:54] - board type
                  0b00 - CZ.NIC Turris Mox
                  0b01 - reserved (unassigned)
                  0b10 - RIPE Atlas Probe
                  0b11 - reserved (unassigned)
      [57:56] - RAM size
                  0b00 -  512M
                  0b01 - 1024M
                  0b10 - 2048M
                  0b11 - 4096M
      [63:58] - reserved (zeros)
      [64]    - lock bit (1 - if above data are valid)

    row 43
      [63:00] - 64-bit device serial number in big endian with swapped 32-bit words
        [07:00] - first byte of serial (MSB)
        [15:08] - second byte of serial
        [23:16] - third byte of serial
        [31:24] - fourth byte of serial (LSB)
        [39:32] - first byte of hw-rev/version (MSB)
        [47:40] - second byte of hw-rev/version
        [55:48] - third byte of hw-rev/version
        [63:56] - fourth byte of hw-rev/version (LSB)
      [64]    - lock bit (1 - if above data are valid)

Armada 3720 Secure OTP rows are mapped 1:1 to U-Boot fuse bank numbers.

Read serial number::

    => fuse read 43 1
    => fuse read 43 0

#!/bin/bash
clear

# Initia script by @glewarne big thanks!

# What you need installed to compile
# gcc, gpp, cpp, c++, g++, lzma, lzop, ia32-libs

# What you need to make configuration easier by using xconfig
# qt4-dev, qmake-qt4, pkg-config

# Setting the toolchain
# the kernel/Makefile CROSS_COMPILE variable to match the download location of the
# bin/ folder of your toolchain
# toolchain already axist and set! in kernel git. android-toolchain/bin/

# Structure for building and using this script

# location
KERNELDIR=$(readlink -f .);
export PATH=$PATH:tools/lz4demo

CLEANUP()
{
	# begin by ensuring the required directory structure is complete, and empty
	echo "Initialising................."
	rm -f "$KERNELDIR"/READY-KERNEL/system/lib/modules/*
	rm -rf "$KERNELDIR"/READY-KERNEL/boot
	rm -f "$KERNELDIR"/READY-KERNEL/*.zip
	rm -f "$KERNELDIR"/READY-KERNEL/*.img
	mkdir -p "$KERNELDIR"/READY-KERNEL/boot

	# force regeneration of .dtb and zImage files for every compile
	rm -f arch/arm/boot/*.dtb
	rm -f arch/arm/boot/*.cmd
	rm -f arch/arm/boot/zImage
	rm -f arch/arm/boot/Image

	BUILD_L01F=0
}
CLEANUP;

BUILD_NOW()
{
	#if [ -e /usr/bin/python3 ]; then
	#	rm /usr/bin/python
	#	ln -s /usr/bin/python2 /usr/bin/python
	#fi;

	# move into the kernel directory and compile the main image
	echo "Compiling Kernel.............";
	if [ ! -f "$KERNELDIR"/.config ]; then
		if [ "$BUILD_L01F" -eq "1"]; then
			cp arch/arm/configs/simon_l01f_defconfig .config
		fi;
	fi;

	if [ -f "$KERNELDIR"/.config ]; then
		BRANCH_L01F=$(grep -R "CONFIG_MACH_MSM8974_G2_DCM=y" .config | wc -l)
		if [ "$BRANCH_L01F" -eq "0" ] && ["$BUILD_L01F" -eq "1" ]; then
			cp arch/arm/configs/simon_l01f_defconfig ./.config
		fi;
	fi;

	# get version from config
	#GETVER=$(grep 'Kernel-.*-V' .config |sed 's/Kernel-//g' | sed 's/.*".//g' | sed 's/-L.*//g');
	#GETBRANCH=$(grep '.*-LG' .config |sed 's/Kernel-Dorimanx-V//g' | sed 's/[1-9].*-LG-//g' | sed 's/.*".//g' | sed 's/-PWR.*//g');

	# remove all old modules before compile
	for i in $(find "$KERNELDIR"/ -name "*.ko"); do
		rm -f "$i";
	done;

	# Copy needed dtc binary to system to finish the build.
	if [ ! -e /bin/dtc ]; then
		cp -a scripts/dtc/dtc /bin/;
	fi;

	# Idea by savoca
	NR_CPUS=$(grep -c ^processor /proc/cpuinfo)

	if [ "$NR_CPUS" -le "2" ]; then
		NR_CPUS=4;
		echo "Building kernel with 4 CPU threads";
	else
		echo "Building kernel with $NR_CPUS CPU threads";
	fi;

	# build zImage
	time make -j ${NR_CPUS}

	cp "$KERNELDIR"/.config "$KERNELDIR"/arch/arm/configs/"$KERNEL_CONFIG_FILE";

	stat "$KERNELDIR"/arch/arm/boot/zImage || exit 1;

	# compile the modules, and depmod to create the final zImage
	echo "Compiling Modules............"
	time make modules -j ${NR_CPUS} || exit 1

	# move the compiled zImage and modules into the READY-KERNEL working directory
	echo "Move compiled objects........"

	for i in $(find "$KERNELDIR" -name '*.ko'); do
		cp -av "$i" ./READY-KERNEL/system/lib/modules/;
	done;

	chmod 755 ./READY-KERNEL/system/lib/modules/*

	if [ -e "$KERNELDIR"/arch/arm/boot/zImage ]; then
		cp arch/arm/boot/zImage READY-KERNEL/boot

		cp ramdisk.lz4 READY-KERNEL/boot

		# create the dt.img from the compiled device files, necessary for msm8974 boot images
		echo "Create dt.img................"
		./scripts/dtc/dtc -p 1024 -O dtb -o arch/arm/boot/msm8974-g2-dcm.dtb arch/arm/boot/dts/lge/msm8974-g2/msm8974-g2-dcm/msm8974-g2-dcm.dts
		./scripts/dtc/dtc -p 1024 -O dtb -o arch/arm/boot/msm8974-v2-g2-dcm.dtb arch/arm/boot/dts/lge/msm8974-g2/msm8974-g2-dcm/msm8974-v2-g2-dcm.dts
		./scripts/dtc/dtc -p 1024 -O dtb -o arch/arm/boot/msm8974-v2-2-g2-dcm.dtb arch/arm/boot/dts/lge/msm8974-g2/msm8974-g2-dcm/msm8974-v2-2-g2-dcm.dts
		./scripts/dtbTool -v -s 2048 -o READY-KERNEL/boot/dt.img -p scripts/dtc/  arch/arm/boot/

		# add kernel config to kernle zip for other devs
		cp "$KERNELDIR"/.config READY-KERNEL/

		# build the final boot.img ready for inclusion in flashable zip
		echo "Build boot.img..............."
		cp scripts/mkbootimg READY-KERNEL/boot
		cd READY-KERNEL/boot
		base=0x00000000
		offset=0x05000000
		tags_addr=0x00000100
		cmd_line="console=ttyHSL0,115200,n8 user_debug=31 ehci-hcd.park=3 msm_rtb.filter=0x37 androidboot.hardware=g2 androidboot.selinux=permissive"
		./mkbootimg --kernel zImage --ramdisk ramdisk.lz4 --cmdline "$cmd_line" --base $base --offset $offset --tags-addr $tags_addr --pagesize 2048 --dt dt.img -o newboot.img
		mv newboot.img ../boot.img

		# cleanup all temporary working files
		echo "Post build cleanup..........."
		cd ..
		rm -rf boot

		# BUMP boot.img with magic key to install on JB/KK bootloader
		cd ..
		sh kernel_bump.sh
		mv READY-KERNEL/boot_bumped.img READY-KERNEL/boot.img
		echo "Kernel BUMP done!";
		cd READY-KERNEL/

		# create the flashable zip file from the contents of the output directory
		echo "Make flashable zip..........."
		zip -r Kernel-Simon-LP-"$(date +"%H-%M-%d-%m-LG-L01F-V1.1")".zip * >/dev/null
		stat boot.img
		rm -f ./*.img
		cd ..
	else
		# with red-color
		echo -e "\e[1;31mKernel STUCK in BUILD! no zImage exist\e[m"
	fi;
}

CLEAN_KERNEL()
{
	# fix python
	if [ -e /usr/bin/python3 ]; then
		rm /usr/bin/python
		ln -s /usr/bin/python2 /usr/bin/python
	fi;

	cp -pv .config .config.bkp;
	make ARCH=arm mrproper;
	make clean;
	cp -pv .config.bkp .config;

}

export KERNEL_CONFIG=simon_l01f_defconfig
KERNEL_CONFIG_FILE=simon_l01f_defconfig
BUILD_L01F=1;
BUILD_NOW;

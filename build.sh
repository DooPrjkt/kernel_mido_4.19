#!/bin/bash

set -e

yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\e[0;32m'

echo -e "$green << cleanup >> \n $white"
rm -rf out zip error.log

MY_DIR="${BASH_SOURCE%/*}"
[[ ! -d "$MY_DIR" ]] && MY_DIR="$PWD"

# ===== TELEGRAM FROM SECRETS =====
: "${CHATID:?CHATID not set}"
: "${API_BOT:?API_BOT not set}"

DEVICE="Redmi Note 4/4X"
CODENAME="mido"
KERNEL_NAME="DooPrjkt"
DEFCONFIG="vendor/mido_defconfig"

AnyKernel="https://github.com/DooPrjkt/AnyKernel3.git"
AnyKernelbranch="mido"

HOSST="Buildbot"
USEER="DooPrjkt"
TOOLCHAIN="clang"

export BOT_MSG_URL="https://api.telegram.org/bot$API_BOT/sendMessage"
export BOT_BUILD_URL="https://api.telegram.org/bot$API_BOT/sendDocument"

tg_post_msg() {
curl -s -X POST "$BOT_MSG_URL" \
-d chat_id="$2" \
-d "parse_mode=html" \
-d text="$1"
}

tg_post_build() {
MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
-F chat_id="$2" \
-F "disable_web_page_preview=true" \
-F "parse_mode=html" \
-F caption="Build finished in $(($Diff / 60))m $(($Diff % 60))s | <b>MD5:</b> <code>$MD5CHECK</code>"
}

# ===== TOOLCHAIN =====
if [ "$TOOLCHAIN" == clang ]; then
if [ ! -d "$HOME/proton_clang" ]; then
git clone --depth=1 https://github.com/kdrag0n/proton-clang.git "$HOME"/proton_clang
fi
export PATH="$HOME/proton_clang/bin:$PATH"
fi

build_kernel() {
Start=$(date +"%s")

make -j$(nproc --all) O=out \
ARCH=arm64 \
CC="ccache clang" \
AR=llvm-ar \
NM=llvm-nm \
STRIP=llvm-strip \
OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump \
OBJSIZE=llvm-size \
READELF=llvm-readelf \
HOSTCC=clang \
HOSTCXX=clang++ \
HOSTAR=llvm-ar \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
2>&1 | tee error.log

End=$(date +"%s")
Diff=$(($End - $Start))
}

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_HOST="$HOSST"
export KBUILD_BUILD_USER="$USEER"

mkdir -p out
make O=out clean && make O=out mrproper
make "$DEFCONFIG" O=out

tg_post_msg "<code>Building kernel...</code>" "$CHATID"

build_kernel

IMG="$MY_DIR/out/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
echo -e "$red Build failed $white"
tg_error "error.log" "$CHATID"
exit 1
fi

DATE=$(date +"%Y%m%d-%H%M%S")
KERVER=$(make kernelversion)

echo -e "$green Build success $white"

echo -e "$green Cloning AnyKernel $white"
git clone --depth=1 -b "$AnyKernelbranch" "$AnyKernel" zip || { echo "Clone failed"; exit 1; }

cp "$IMG" zip/
cd zip
mv Image.gz-dtb zImage

ZIP="$KERNEL_NAME-$CODENAME-$DATE"

echo -e "$yellow Creating zip $white"
zip -r9 "$ZIP".zip * -x "*.git*" "README.md"

tg_post_msg "<b>$KERNEL_NAME for $CODENAME</b>%0A<b>Kernel:</b> <code>$KERVER</code>%0A<b>Date:</b> <code>$(date)</code>" "$CHATID"

tg_post_build "$ZIP".zip "$CHATID"

cd ..
rm -rf out zip error.log

echo -e "$green Done $white"

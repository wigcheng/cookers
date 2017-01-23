TOP="${PWD}"
PATH_KERNEL="${PWD}/linux-am335x"
PATH_UBOOT="${PWD}/u-boot"
LINUX_ROOTFS=lede-omap-default-rootfs.tar.gz

export PATH="${PATH_UBOOT}/tools:${PATH}"
export ARCH=arm
export CROSS_COMPILE="${PWD}/toolchain/bin/arm-linux-gnueabihf-"

# TARGET support: wandboard,edm1cf,picosom,edm1cf_6sx
IMX_PATH="./mnt"
MODULE=$(basename $BASH_SOURCE)
CPU_TYPE=$(echo $MODULE | awk -F. '{print $3}')
CPU_MODULE=$(echo $MODULE | awk -F. '{print $4}')
BASEBOARD=$(echo $MODULE | awk -F. '{print $5}')


if [[ "$CPU_TYPE" == "imx6" ]]; then
    if [[ "$CPU_MODULE" == "bf8a1" ]]; then
        if [[ "$BASEBOARD" == "bf8a1" ]]; then
            UBOOT_CONFIG='mx6_bf8a1_defconfig'
            KERNEL_IMAGE='zImage'
            KERNEL_CONFIG='tn_imx_bf8a1_defconfig'
            DTB_TARGET='imx6q-bf8a1.dtb'
        fi
    fi

elif [[ "$CPU_TYPE" == "am335x" ]]; then
    if [[ "$CPU_MODULE" == "st7b2" ]]; then
        if [[ "$BASEBOARD" == "st7b2" ]]; then
            UBOOT_CONFIG='am335x_st7b2_defconfig'
            KERNEL_IMAGE='zImage'
            KERNEL_CONFIG='nutsboard_defconfig'
            DTB_TARGET='am335x-st7b2.dtb'
        fi
    fi

elif [[ "$CPU_TYPE" == "nutsboard" ]]; then
    if [[ "$CPU_MODULE" == "almond" ]]; then
        if [[ "$BASEBOARD" == "walnut" ]]; then
            UBOOT_CONFIG='nutsboard_almond_defconfig'
            KERNEL_IMAGE='zImage'
            KERNEL_CONFIG='nutsboard_defconfig'
            DTB_TARGET='am335x-nutsboard-almond.dtb'
        fi


    fi
fi

recipe() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" menuconfig || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

heat() {
    local TMP_PWD="${PWD}"
    case "${PWD}" in
        "${TOP}")
            cd "${TMP_PWD}"
            cd ${PATH_UBOOT} && heat "$@" || return $?
            cd ${PATH_KERNEL} && heat "$@" || return $?
            cd "${TMP_PWD}"
            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" $KERNEL_IMAGE || return $?
            make "$@" modules || return $?
            make "$@" $DTB_TARGET || return $?
            rm -rf ./modules
            make modules_install INSTALL_MOD_PATH=./modules/
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

cook() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${TOP}")
            cd ${PATH_UBOOT} && cook "$@" || return $?
            cd ${PATH_KERNEL} && cook "$@" || return $?
            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" $KERNEL_CONFIG || return $?
            heat "$@" || return $?
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" $UBOOT_CONFIG || return $?
            heat "$@" || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

throw() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${TOP}")
            rm -rf out
            cd ${PATH_UBOOT} && throw "$@" || return $?
            cd ${PATH_KERNEL} && throw "$@" || return $?
            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" distclean || return $?
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" distclean || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

flashcard() {
    local TMP_PWD="${PWD}"
    sd_node="$@"
    echo $sd_node
    if [[ "$CPU_TYPE" == "am335x" ]]; then
      mkdir mnt

      (echo 2; echo n) | sudo ./cookers/create-sdcard.sh sde

      echo"============ flashing the U-boot ================"
      sudo mount /dev/${sd_node}1 mnt
      sudo cp -rv $PATH_UBOOT/MLO mnt/
      sudo cp -rv $PATH_UBOOT/u-boot.img mnt/
      sudo cp -rv $PATH_UBOOT/board/tailyn/$BASEBOARD/uEnv.txt mnt/
      sync;

      echo"============ flashing the Kernel ================"
      sudo cp -rv $PATH_KERNEL/arch/arm/boot/zImage mnt/
      sudo cp -rv $PATH_KERNEL/arch/arm/boot/dts/$DTB_TARGET mnt/

      sudo umount mnt
      sync;
      sudo mount /dev/${sd_node}2 mnt

      echo"============ flashing the rootfs ================"
      cd mnt
      sudo tar zxvf ../"$LINUX_ROOTFS"
      cd -
      sync;

      echo"============ flashing the Kernel Modules ================"
      sudo rm -rf mnt/lib/modules/*
      sudo mkdir -p mnt/lib/modules/
      sudo cp -rv $PATH_KERNEL/modules/lib/modules/* mnt/lib/modules/
      sudo umount mnt
      rm -rf mnt
   fi
}

ubi_create() {

  local TMP_PWD="${PWD}"
  sd_node="$@"
  echo $sd_node
  mkdir mnt
  sudo  mount ${sd_node}2 mnt

  sudo mkfs.ubifs -F -q -r mnt -m 2048 -e 126976 -c 2047 -o ubifs.img
  sync;
  sudo ubinize -o ubi.img -m 2048 -p 128KiB -s 2048 cookers/ubinize.cfg
  sync;

  sudo rm ubifs.img
  sudo umount mnt
  rm -rf mnt
}

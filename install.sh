#!/bin/bash -e

WORKDIR="$(dirname $(realpath $0))"

install_dependencies() {
    apt install -y linux-headers-`uname -r` git dkms
}

update_git() {
    SYSTEM_KERNEL_VERSION="`uname -r | grep -Po ^[0-9]+\.[0-9]+`"
    if [ "${SYSTEM_KERNEL_VERSION:0:1}" -ge "6" ] & [ "${SYSTEM_KERNEL_VERSION:2}" -ge "6" ]; then
        TARGET_BRANCH="linux-msft-wsl-6.6.y";
    else
        TARGET_BRANCH="linux-msft-wsl-5.15.y";
    fi

    if [ ! -e "/tmp/WSL2-Linux-Kernel" ]; then
        git clone --branch=$TARGET_BRANCH --no-checkout --depth=1 https://github.com/microsoft/WSL2-Linux-Kernel.git /tmp/WSL2-Linux-Kernel
    fi

    cd /tmp/WSL2-Linux-Kernel;

    if [ "`git branch -a | grep -o $TARGET_BRANCH`" == "" ]; then
        git fetch --depth=1 origin $TARGET_BRANCH:$TARGET_BRANCH;
    fi

    git sparse-checkout set --no-cone /drivers/hv/dxgkrnl /include/uapi/misc/d3dkmthk.h
    git checkout -f $TARGET_BRANCH
}

get_version() {
    cd /tmp/WSL2-Linux-Kernel

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    VERSION=$(git rev-parse --short HEAD)
}

install() {
    cd /tmp/WSL2-Linux-Kernel

    case $CURRENT_BRANCH in
        "linux-msft-wsl-5.15.y")
            PATCHES="linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch \
                    linux-msft-wsl-5.15.y/0002-Add-a-multiple-kernel-version-support.patch \
                    linux-msft-wsl-5.15.y/0003-Fix-gpadl-has-incomplete-type-error.patch";

            for PATCH in $PATCHES; do
                # Patch source files
                if [ -e "$WORKDIR/$PATCH" ]; then
                    cat "$WORKDIR/$PATCH" | git apply -v;
                else
                    curl -fsSL "https://content.staralt.dev/dxgkrnl-dkms/main/$PATCH" | git apply -v;
                fi
                echo;
            done
            ;;
        "linux-msft-wsl-6.6.y")
            PATCHES="linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch \
                    linux-msft-wsl-6.6.y/0002-Fix-eventfd_signal.patch";

            for PATCH in $PATCHES; do
                # Patch source files
                if [ -e "$WORKDIR/$PATCH" ]; then
                    cat "$WORKDIR/$PATCH" | git apply -v;
                else
                    curl -fsSL "https://content.staralt.dev/dxgkrnl-dkms/main/$PATCH" | git apply -v;
                fi
                echo;
            done
            ;;
        *)
            >&2 echo "Fatal: \"$CURRENT_BRANCH\" is not available";
            exit 1;;
    esac

    # Copy source files
    echo -e "Copy: \n  \"/tmp/WSL2-Linux-Kernel/drivers/hv/dxgkrnl\" -> \"/usr/src/dxgkrnl-$VERSION\""
    cp -r ./drivers/hv/dxgkrnl /usr/src/dxgkrnl-$VERSION

    # Copy include files
    echo -e "Copy: \n  \"/tmp/WSL2-Linux-Kernel/include\" -> \"/usr/src/dxgkrnl-$VERSION/include\""
    cp -r ./include /usr/src/dxgkrnl-$VERSION/include

    # Patch a Makefile
    sed -i 's/\$(CONFIG_DXGKRNL)/m/' /usr/src/dxgkrnl-$VERSION/Makefile
    echo "EXTRA_CFLAGS=-I\$(PWD)/include -D_MAIN_KERNEL_" >> /usr/src/dxgkrnl-$VERSION/Makefile # !important

    # Create a config of DKMS
    # https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a
    cat > /usr/src/dxgkrnl-$VERSION/dkms.conf << EOF
PACKAGE_NAME="dxgkrnl"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME="dxgkrnl"
DEST_MODULE_LOCATION="/kernel/drivers/hv/dxgkrnl/"
AUTOINSTALL="yes"
EOF
}

install_dkms() {
    dkms add dxgkrnl/$VERSION
    dkms build dxgkrnl/$VERSION
    dkms install dxgkrnl/$VERSION
}

all() {
    echo -e "\nInstalling dependencies...\n"
    install_dependencies

    echo
    update_git
    get_version

    echo -e "\nModule Version: ${CURRENT_BRANCH} @ ${VERSION}\n"
    echo -e "Installing a module. Please wait...\n"
    install
    install_dkms
}

help() {
    echo
    echo "Usage:"
    echo "  $0 - Install a latest module."
    echo
    echo "  $0 clean all - Remove all modules."
    echo "  $0 clean [version] - Remove a specific version module."
    echo
    exit 0
}

clean() {
    if [[ ! -e /sbin/dkms ]]; then
        echo "dkms is not installed"
        exit 1
    fi

    if [ -z "$1" ]; then
        echo
        echo "Usage:"
        echo "  $0 clean all - Remove all modules."
        echo "  $0 clean [version] - Remove a specific version module."
        echo
        exit 0
    elif [ "$1" == "all" ]; then
        TARGETS=`dkms status dxgkrnl | grep -E "dxgkrnl/[a-z0-9]+" -o | awk '!a[$0]++'`
        if [ -z $TARGETS ]; then
            echo "Ignored. There is no modules to clean."
            exit 0
        fi

        for TARGET in $TARGETS; do
            dkms remove "$TARGET"
            rm -r "/usr/src/dxgkrnl-${TARGET:8}"
            echo
        done
    else
        dkms remove "dxgkrnl/$1"
        rm -r "/usr/src/dxgkrnl-$1"
        echo
    fi
}

if [ -z $1 ]; then
    all
elif [ "$1" = "clean" ]; then
    shift
    clean "$@"
else
    help
fi

echo "Done."
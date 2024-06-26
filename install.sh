#!/bin/bash -e

install_dependencies() {
    apt install -y linux-headers-`uname -r` git dkms
}

update_git() {
    if [ ! -e "/tmp/WSL2-Linux-Kernel" ]; then
        git clone --no-checkout --depth=1 https://github.com/microsoft/WSL2-Linux-Kernel.git /tmp/WSL2-Linux-Kernel
    fi

    cd /tmp/WSL2-Linux-Kernel
    git sparse-checkout set --no-cone /drivers/hv/dxgkrnl /include/uapi/misc/d3dkmthk.h
    git checkout -f
}

get_version() {
    cd /tmp/WSL2-Linux-Kernel

    BRANCH=$(git name-rev --name-only --tags HEAD)
    VERSION=$(git rev-parse --short HEAD)
}

install() {
    cd /tmp/WSL2-Linux-Kernel

    # Patch source files
    curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/0001-Add-a-gpu-pv-support.patch | git apply -v
    echo
    curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/0002-Add-a-multiple-kernel-version-support.patch | git apply -v
    echo
    curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/0003-Fix-gpadl-has-incomplete-type-error.patch | git apply -v
    echo
    
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

    echo -e "\nModule Version: ${BRANCH} @ ${VERSION}\n"
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
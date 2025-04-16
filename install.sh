#!/bin/bash -e

echo "staralt/dxgkrnl-dkms v2025.04 (https://git.staralt.dev/dxgkrnl-dkms)"
echo

WORKDIR="$(dirname $(realpath $0))"
LINUX_DISTRO="$(cat /etc/*-release)"
LINUX_DISTRO=${LINUX_DISTRO,,}

KERNEL_6_6_NEWER_REGEX="^(6\.[6-9]\.|6\.[0-9]{2,}\.)"
KERNEL_5_15_NEWER_REGEX="^(5\.1[5-9]+\.)"

INSTALL_DEPENDENCIES='Y'
INSTALL_VGEM='N'
TARGET_KERNEL_VERSION=""
FORCE=""

parse_option() {
	NEXT=""
    for opt in $@; do
		if [ ! -z "$NEXT" ]; then
			case "$NEXT" in
				"K") 
					if [[ "$opt" =~ ^[0-9]+\.[0-9]+\.[0-9]+.+$ ]]; then
                    	TARGET_KERNEL_VERSION="$opt";
                	else
                    	>&2 echo -e "Fatal: Incorrect kernel version '$opt' (expected format is '`ls /lib/modules | head -n1`')\n"
                    	exit 1;
                	fi
			esac
			NEXT=""
		elif [[ "$opt" =~ ^\-[a-z]{2,}$ ]]; then
			for v in `echo "${opt:1}" | grep -o .`; do
				case "$v" in
					"k")
						>&2 echo -e "Fatal: Option '-k' must be used alone.\n"
						exit 1;
					;;
					"g") INSTALL_VGEM="Y";;
					"n") INSTALL_DEPENDENCIES="N";;
					"f") FORCE="--force";;
					*) 
						>&2 echo -e "Fatal: Cannot parse argument '-$v' in '$opt' (use '-h' to see usage)\n"
						exit 1
					;;
				esac
			done
		elif [[ "$opt" =~ ^\-[a-z\-]+$ ]]; then
        	case "$opt" in
				"-k"|"--kernel") NEXT="K";;
            	"-g"|"--install-vgem") INSTALL_VGEM='Y';;
            	"-n"|"--no-install-dependencies") INSTALL_DEPENDENCIES='N';;
            	"-f"|"--force") FORCE="--force";;
            	*)
					>&2 echo -e "Fatal: Cannot parse argument '$opt' (use -h to see usage)\n"
					exit 1
				;;
        	esac
		else
			>&2 echo -e "Fatal: Cannot parse argument '$opt' (use -h to see usage)\n"
			exit 1
		fi
    done;

	if [ ! -z "$NEXT" ]; then
		case "$NEXT" in
			"K")
				>&2 echo -e "Fatal: Kernel version not passed.\n"
				exit 1
			;;
		esac
	fi

    if [ "$TARGET_KERNEL_VERSION" == ""  ]; then
        TARGET_KERNEL_VERSION="`uname -r`";
    fi
}

install_dependencies() {
    NEED_TO_INSTALL=""
    if [ ! -e "/bin/git" ] && [ ! -e "/usr/bin/git" ]; then
        NEED_TO_INSTALL="git"; 
    fi
    if [ ! -e "/sbin/dkms" ] && [ ! -e "/bin/dkms" ] && [ ! -e "/usr/bin/dkms" ]; then
        NEED_TO_INSTALL="$NEED_TO_INSTALL dkms"
    fi
    if [ ! -e "/usr/src/linux-headers-${TARGET_KERNEL_VERSION}" ]; then
        NEED_TO_INSTALL="$NEED_TO_INSTALL linux-headers-${TARGET_KERNEL_VERSION}";
    fi

    if [[ -z "$NEED_TO_INSTALL" ]]; then
        echo "All dependencies are already installed."
        return 0;
    fi

    if [[ "$LINUX_DISTRO" == *"debian"* ]]; then
        apt update;
        apt install -y $NEED_TO_INSTALL;
    elif [[ "$LINUX_DISTRO" == *"fedora"* ]]; then
        yum -y install $NEED_TO_INSTALL;
    else
        >&2 echo "Fatal: The system distro is unsupported";
        >&2 echo "If your system is based on 'Debian' or 'Fedora', please report this issue with the following information.";
        >&2 echo "https://git.staralt.dev/dxgkrnl-dkms/issues";
        >&2 echo;
        >&2 cat /etc/*-release;
        exit 1;
    fi
}

update_git() {
    if [[ "${TARGET_KERNEL_VERSION}" =~ $KERNEL_6_6_NEWER_REGEX ]]; then
        TARGET_BRANCH="linux-msft-wsl-6.6.y";
    elif [[ "${TARGET_KERNEL_VERSION}" =~ $KERNEL_5_15_NEWER_REGEX ]]; then
        TARGET_BRANCH="linux-msft-wsl-5.15.y";
    else
        >&2 echo "Fatal: Unsupported kernel version (5.15.0 <=)";
        exit 1;
    fi

    if [ ! -e "/tmp/WSL2-Linux-Kernel" ]; then
        git clone --branch=$TARGET_BRANCH --no-checkout --depth=1 https://github.com/microsoft/WSL2-Linux-Kernel.git /tmp/WSL2-Linux-Kernel
    fi

    cd /tmp/WSL2-Linux-Kernel;

    if [ "`git branch -a | grep -o $TARGET_BRANCH`" == "" ]; then
        git fetch --depth=1 origin $TARGET_BRANCH:$TARGET_BRANCH;
    fi

    git sparse-checkout set --no-cone /drivers/hv/dxgkrnl /drivers/gpu/drm/vgem /include/uapi/misc/d3dkmthk.h
    git checkout -f $TARGET_BRANCH
}

get_version() {
    cd /tmp/WSL2-Linux-Kernel

    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    VERSION=$(git rev-parse --short HEAD)
}

install_dxgkrnl() {
    cd /tmp/WSL2-Linux-Kernel

    case $CURRENT_BRANCH in
        "linux-msft-wsl-5.15.y")
            PATCHES="linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch \
                    linux-msft-wsl-5.15.y/0002-Add-a-multiple-kernel-version-support.patch";
            if [[ "$TARGET_KERNEL_VERSION" != *"azure"* ]]; then
                    PATCHES="$PATCHES linux-msft-wsl-5.15.y/0003-Fix-gpadl-has-incomplete-type-error.patch";
            fi
            
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
            PATCHES="linux-msft-wsl-5.15.y/0001-Add-a-gpu-pv-support.patch";
            if [[ "$TARGET_KERNEL_VERSION" != *"truenas"* ]]; then
                PATCHES="$PATCHES linux-msft-wsl-6.6.y/0002-Fix-eventfd_signal.patch";
            fi

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
    echo "EXTRA_CFLAGS=-I\$(PWD)/include -D_MAIN_KERNEL_ \
                       -I/usr/src/linux-headers-\${kernelver}/include/linux \
                       -include /usr/src/linux-headers-\${kernelver}/include/linux/vmalloc.h" >> /usr/src/dxgkrnl-$VERSION/Makefile # !important

    if [[ "${TARGET_KERNEL_VERSION}" =~ $KERNEL_6_6_NEWER_REGEX ]]; then
        BUILD_EXCLUSIVE_KERNEL=$KERNEL_6_6_NEWER_REGEX
    else
        BUILD_EXCLUSIVE_KERNEL=$KERNEL_5_15_NEWER_REGEX
    fi

    # Create a config of DKMS
    # https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a
    cat > /usr/src/dxgkrnl-$VERSION/dkms.conf << EOF
PACKAGE_NAME="dxgkrnl"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME="dxgkrnl"
DEST_MODULE_LOCATION="/kernel/drivers/hv/dxgkrnl/"
AUTOINSTALL="yes"
BUILD_EXCLUSIVE_KERNEL="$BUILD_EXCLUSIVE_KERNEL"
EOF

    dkms -k ${TARGET_KERNEL_VERSION} add dxgkrnl/$VERSION
    dkms -k ${TARGET_KERNEL_VERSION} build dxgkrnl/$VERSION $FORCE
    dkms -k ${TARGET_KERNEL_VERSION} install dxgkrnl/$VERSION $FORCE
}


install_vgem() {
    cd /tmp/WSL2-Linux-Kernel

    # Copy source files
    echo -e "Copy: \n  \"/tmp/WSL2-Linux-Kernel/drivers/gpu/drm/vgem\" -> \"/usr/src/vgem-$VERSION\""
    cp -r ./drivers/gpu/drm/vgem /usr/src/vgem-$VERSION

    # Copy include files
   # echo -e "Copy: \n  \"/tmp/WSL2-Linux-Kernel/include\" -> \"/usr/src/vgem-$VERSION/include\""
    #cp -r ./include /usr/src/vgem-$VERSION/include

    # Patch a Makefile
    sed -i 's/\$(CONFIG_DRM_VGEM)/m/' /usr/src/vgem-$VERSION/Makefile
    echo "EXTRA_CFLAGS=-D_MAIN_KERNEL_ \
                       -I/usr/src/linux-headers-\${kernelver}/include/linux \
                       -include /usr/src/linux-headers-\${kernelver}/include/linux/vmalloc.h" >> /usr/src/vgem-$VERSION/Makefile # !important

    if [[ "${TARGET_KERNEL_VERSION}" =~ $KERNEL_6_6_NEWER_REGEX ]]; then
        BUILD_EXCLUSIVE_KERNEL=$KERNEL_6_6_NEWER_REGEX
    else
        BUILD_EXCLUSIVE_KERNEL=$KERNEL_5_15_NEWER_REGEX
    fi

    # Create a config of DKMS
    # https://gist.github.com/krzys-h/e2def49966aa42bbd3316dfb794f4d6a
    cat > /usr/src/vgem-$VERSION/dkms.conf << EOF
PACKAGE_NAME="vgem"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME="vgem"
DEST_MODULE_LOCATION="/kernel/drivers/gpu/drm/vgem/"
AUTOINSTALL="yes"
BUILD_EXCLUSIVE_KERNEL="$BUILD_EXCLUSIVE_KERNEL"
EOF

    dkms -k ${TARGET_KERNEL_VERSION} add vgem/$VERSION
    dkms -k ${TARGET_KERNEL_VERSION} build vgem/$VERSION $FORCE
    dkms -k ${TARGET_KERNEL_VERSION} install vgem/$VERSION $FORCE
}

all() {
    parse_option "$@"

	echo "- Install dependencies: $INSTALL_DEPENDENCIES"
	echo "- Install vgem:		$INSTALL_VGEM"
	echo

    echo -e "Target Kernel Version: ${TARGET_KERNEL_VERSION}\n"

    if [ "$INSTALL_DEPENDENCIES" == "Y" ]; then
		sleep 2;
        echo -e "Installing dependencies...\n"
        install_dependencies
    else
		if [ ! -e "/sbin/dkms" ]; then
			>&2 echo -e "Fatal: Dkms is not installed.\n"
			exit 1;
		elif [ ! -e "/bin/git" ] || [ ! -e "/usr/bin/git" ]; then
			>&2 echo -e "Fatal: Git is not installed.\n"
			exit 1;
		elif [ ! -e "/usr/src/linux-headers-${TARGET_KERNEL_VERSION}" ]; then
			>&2 echo -e "Fatal: Header file (/usr/src/linux-headers-${TARGET_KERNEL_VERSION}) does not exist.\n"
			exit 1;
		fi
	fi

    update_git
    get_version

    echo -e "\nModule Version: ${CURRENT_BRANCH} @ ${VERSION}\n"
    echo -e "Installing dxgkrnl module. Please wait...\n"
    install_dxgkrnl

    if [ "$INSTALL_VGEM" == "Y" ]; then
        echo -e "\nInstalling vgem module. Please wait...\n"
        install_vgem 
    fi
}

help() {
    echo "Usage:"
	echo "    $0 [opts]			Install a module"
    echo
    echo "    $0 clean all		Remove all modules"
    echo "    $0 clean [module ver]	Remove a specific version module"
    echo
    echo "Options:"		
    echo "    -k | --kernel [kernel ver]		Select a kernel to install modules (default: `uname -r`)"
	echo
    echo "    -g | --install-vgem 		Install vgem to use hardware acceleration"
    echo "    -n | --no-install-dependencies 	Do not install dependencies before build"
	echo "    -f | --force			Force install a module even if it already exists"
    echo
    echo "    -? | -h | --help 			Print help"
    echo
    exit 0
}

clean() {
    if [[ ! -e /sbin/dkms ]]; then
        >&2 echo -e "Fatal: Dkms is not installed.\n"
        exit 1
    fi

    if [ -z "$1" ]; then
        echo "Usage:"
    	echo "    $0 clean all		Remove all modules."
    	echo "    $0 clean [module ver]	Remove a specific version module."
        echo
        exit 0
    elif [ "$1" == "all" ]; then
        TARGETS=`dkms status dxgkrnl | grep -E "dxgkrnl/[a-z0-9]+" -o | awk '!a[$0]++'`
        VGEM_TARGETS=`dkms status vgem | grep -E "vgem/[a-z0-9]+" -o | awk '!a[$0]++'`
        if [ -z "$TARGETS" ] && [ -z "$VGEM_TARGETS" ]; then
            echo "Ignored. There is no modules to clean."
            exit 0
        fi

        for TARGET in $TARGETS; do
            dkms --all remove "$TARGET"
            rm -r "/usr/src/dxgkrnl-${TARGET:8}"
            echo
        done

        for TARGET in $VGEM_TARGETS; do
            dkms --all remove "$TARGET"
            rm -r "/usr/src/vgem-${TARGET:5}"
            echo
        done
    else
        dkms --all remove "dxgkrnl/$1" || true
        dkms --all remove "vgem/$1" || true 
        rm -r "/usr/src/dxgkrnl-$1" || true
        rm -r "/usr/src/vgem-$1" || true
        echo
    fi
}

if [ -z $1 ]; then
    all "-k `uname -r`"
elif [[ "$@" =~ \-[a-z]*h[a-z]*|\-help|\-\? ]]; then
    help
elif [ "$1" = "clean" ]; then
    shift
    clean "$@"
else
    all "$@"
fi

echo "Done."
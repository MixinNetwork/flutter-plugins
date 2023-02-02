#  Choose your libopus version and your currently-installed iOS SDK version:
#  xcodebuild -showsdks to check currently-installed iOS SDK.
VERSION="1.3.1"
SDKVERSION="16.2"
MINIOSVERSION="10.0"

source function.sh

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/opus-${VERSION}.tar.gz" ]; then
	echo "Downloading opus-${VERSION}.tar.gz"
	curl -LO http://downloads.xiph.org/releases/opus/opus-${VERSION}.tar.gz
fi
echo "Using opus-${VERSION}.tar.gz"

tar zxf opus-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/opus-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=`which ccache`
if [ $? == "0" ]; then
	echo "Building with ccache: $CCACHE"
	CCACHE="${CCACHE} "
else
	echo "Building without ccache"
	CCACHE=""
fi
set -e # back to regular "bail out on error" mode

export ORIGINALPATH=$PATH

OPTION_CONFIG="${OPTION_CONFIG} --disable-extra-programs"

build_arch_library

########################################

echo "Build library..."


collect_build_library opus

####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/libopus-${VERSION}"
echo "Done."
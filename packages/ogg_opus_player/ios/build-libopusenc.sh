#  Choose your libopusenc version and your currently-installed iOS SDK version:
#  xcodebuild -showsdks to check currently-installed iOS SDK.
VERSION="0.2.1"
SDKVERSION="16.2"
MINIOSVERSION="10.0"

source function.sh

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/libopusenc-${VERSION}.tar.gz" ]; then
	echo "Downloading libopusenc-${VERSION}.tar.gz"
	curl -LO http://downloads.xiph.org/releases/opus/libopusenc-${VERSION}.tar.gz
fi
echo "Using libopusenc-${VERSION}.tar.gz"

tar zxf libopusenc-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/libopusenc-${VERSION}"

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

OPUS_FRAMEWORK_DIR="${OUTPUTDIR}/Frameworks/libopus.xcframework"

OPTION_CONFIG="${OPTION_CONFIG} --disable-examples"
build_arch_library "$OPUS_FRAMEWORK_DIR"

########################################

echo "Build library..."

collect_build_library opusenc

####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/libopusenc-${VERSION}"
echo "Done."
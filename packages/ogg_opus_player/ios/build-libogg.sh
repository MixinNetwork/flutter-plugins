#!/bin/bash
#  Builds libogg for all three current iPhone targets: iPhoneSimulator-i386,
#  iPhoneOS-armv6, iPhoneOS-armv7.
#
#  Copyright 2012 Mike Tigas <mike@tig.as>
#
#  Based on work by Felix Schulze on 16.12.10.
#  Copyright 2010 Felix Schulze. All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

# Forked from: https://github.com/chrisballinger/Opus-iOS

# Forked from: https://github.com/watson-developer-cloud/swift-sdk/blob/master/Scripts/build-libogg.sh

###########################################################################
#  Choose your libogg version and your currently-installed iOS SDK version:
#  xcodebuild -showsdks to check currently-installed iOS SDK.
VERSION="1.3.5"
SDKVERSION="16.2"
MINIOSVERSION="10.0"

source function.sh

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/libogg-${VERSION}.tar.gz" ]; then
  echo "Downloading libogg-${VERSION}.tar.gz"
  curl -LO http://downloads.xiph.org/releases/ogg/libogg-${VERSION}.tar.gz
fi
echo "Using libogg-${VERSION}.tar.gz"

tar zxf libogg-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/libogg-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=$(which ccache)
if [ $? == "0" ]; then
  echo "Building with ccache: $CCACHE"
  CCACHE="${CCACHE} "
else
  echo "Building without ccache"
  CCACHE=""
fi
set -e # back to regular "bail out on error" mode

export ORIGINALPATH=$PATH

OPTION_CONFIG="${OPTION_CONFIG} --disable-examples"

build_arch_library

########################################

echo "Build library..."

collect_build_library ogg

####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/libogg-${VERSION}"
echo "Done."

// Relative import to be able to reuse the C sources.
//
// Swift Package Manager (like CocoaPods) does not support referencing source
// files outside of the package directory, so this forwarder relatively imports
// the shared implementation in `../src` so that the C sources can be shared
// among all target platforms. See the comment in ../mixin_logger.podspec for
// more information about the equivalent CocoaPods setup.
#include "../../../../src/mixin_logger.cpp"

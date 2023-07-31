#! /bin/bash

function build() {
    arch=$1
    CGO_ENABLED=1 GOOS="darwin" GOARCH="$arch" go build -ldflags "-w -s" -buildmode=c-archive -o ./build/"$arch"/ ./mixin_logger.go
}

build "amd64"
build "arm64"

lipo -create ./build/amd64/mixin_logger.a ./build/arm64/mixin_logger.a -output ../macos/Libs/libmixin_logger.a
cp ./build/arm64/mixin_logger.h ./build/mixin_logger.h
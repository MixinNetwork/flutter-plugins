# libsimple

`libsimple.xcframework` contains a universal macOS dylib assembled from the
official [libsimple v0.7.1 release](https://github.com/wangfenjin/simple/releases/tag/v0.7.1):

- `libsimple-osx-arm64.zip`
  (`b699f0fca1e7d1f8776d067708ecf4d0bcc2d765e4b643862e129058583b885f`)
- `libsimple-osx-x64.zip`
  (`d6f7e9fc9dac3c2bcfb5389618d41f2f0db6ea5a83dd8b9a363cf9b02fa20f95`)

After extracting both archives, create and ad-hoc sign the universal dylib:

```sh
lipo -create \
  libsimple-osx-arm64/libsimple.dylib \
  libsimple-osx-x64/libsimple.dylib \
  -output libsimple.dylib
codesign --force --sign - libsimple.dylib
```

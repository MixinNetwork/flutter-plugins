## 0.3.0

**BREAKING CHANGES**

* remove wrl implementation. `WIN_TOAST_ENABLE_WIN_RT`, `WIN_TOAST_WRL_ACTIVATOR_CLSID`, `WIN_TOAST_ENABLE_WRL` cmake configs
  do not work anymore.
* `WinToast.instance().initialize` required a `clsid` parameter to works on msix

**NEW FEATURES**

* add `WinToast.instance().showToast` to show toast from template.

## 0.2.0

* **BREAKING CHANGE** please read README.md for how to use.
* fix the notification which in notification center can not be clicked.
* fix wired behavior when click the notification.

## 0.1.1

* fix GetCurrentPackageFullName didn't work on Windows7.

## 0.1.0

* fix notification wired name when app package as
  msix. [#142](https://github.com/MixinNetwork/flutter-plugins/issues/142)
  by [daniel-kane-everbridge-com](https://github.com/daniel-kane-everbridge-com)

## 0.0.2

* fix cause crash on Windows 7.

## 0.0.1

* add basic functions.

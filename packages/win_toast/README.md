# win_toast

[![Pub](https://img.shields.io/pub/v/win_toast.svg)](https://pub.dev/packages/win_toast)

show toast on windows platform.

## Getting Started


### Initialize

```dart
// initialize toast with you app, product, company names.
await WinToast.instance().initialize(
          appName: 'win_toast_example',
          productName: 'win_toast_example',
          companyName: 'mixin');
```

[Pick a unique AUMID that will identify your Win32 app](https://docs.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl#classic-win32)

This is typically in the form of [CompanyName].[AppName], but you want to ensure this is unique across all apps (feel free to add some digits at the end).


### Show

```dart
final toast = await WinToast.instance().showToast(
      type: ToastType.text01, title: "Hello");
```


## Credit

https://github.com/mohabouje/WinToast
https://github.com/javacommons/strconv
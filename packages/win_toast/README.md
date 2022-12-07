# win_toast

[![Pub](https://img.shields.io/pub/v/win_toast.svg)](https://pub.dev/packages/win_toast)

show a toast notification on your Windows Notification center.

## Getting Started

### Attention

There are two implementation to pop up a toast notification by this package.
1. [WinRT][win_rt_url]: for normal exe app.

    the winrt implementation is enabled default, you can use it directly.

2. [WRL][wrl_url]: for UWP app which packaged to msix.

    the wrl implementation is **disabled default**, you can enable it by add flowing config to your app `windows/CmakeLists.txt`.
    ```
    set(WIN_TOAST_ENABLE_WRL ON)
    set(WIN_TOAST_WRL_ACTIVATOR_CLSID "your-g-u-id-7C627E401B2F")
    ```
    if wrl is enabled, the built exe will not compatible on Windows7.
  

[win_rt_url]: https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/toast-desktop-apps
[wrl_url]: https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl


### Initialize

```dart
void initialize() {
// initialize toast with you aumId, displayName and iconPath
  WinToast.instance().initialize(
    aumId: 'one.mixin.WinToastExample',
    displayName: 'Example Application',
    iconPath: '',
  );
}
```

[Pick a unique AUMID that will identify your Win32 app](https://docs.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl#classic-win32)

This is typically in the form of [CompanyName].[AppName], but you want to ensure this is unique across all apps (feel
free to add some digits at the end).

### Show

```dart
Future<void> show() {
  const xml = """
<?xml version="1.0" encoding="UTF-8"?>
<toast launch="action=viewConversation&amp;conversationId=9813">
   <visual>
      <binding template="ToastGeneric">
         <text>Andrew sent you a picture</text>
         <text>Check this out, Happy Canyon in Utah!</text>
      </binding>
   </visual>
   <actions>
      <input id="tbReply" type="text" placeHolderContent="Type a reply" />
      <action content="Reply" activationType="background" arguments="action=reply&amp;conversationId=9813" />
      <action content="Like" activationType="background" arguments="action=like&amp;conversationId=9813" />
      <action content="View" activationType="background" arguments="action=viewImage&amp;imageUrl=https://picsum.photos/364/202?image=883" />
   </actions>
</toast>
  """;
  WinToast.instance().showCustomToast(xml: xml);
}

```

## Credit

https://github.com/mohabouje/WinToast
https://github.com/javacommons/strconv
https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl
https://github.com/WindowsNotifications/desktop-toasts
# win_toast

[![Pub](https://img.shields.io/pub/v/win_toast.svg)](https://pub.dev/packages/win_toast)

a flutter plugin that allows users to create and display toast notifications to notification center on the Windows operating system

## Getting Started

### Initialize

```dart
void initialize() {
// initialize toast with you aumId, displayName and iconPath
  WinToast.instance().initialize(
    aumId: 'one.mixin.WinToastExample',
    displayName: 'Example Application',
    iconPath: '',
    clsid: 'your-notification-activator-guid-2EB1AE5198B7',
  );
}
```
   * AUMID
        
      [Pick a unique AUMID that will identify your Win32 app](https://docs.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl#classic-win32)

      > This is typically in the form of [CompanyName].[AppName], but you want to ensure this is unique across all apps (feel free to add some digits at the end).
   
   * MSIX

     if Your app is packaged as [MSIX](https://pub.dev/packages/msix), you need to provide a `clsid` parameter to `WinToast.instance().initialize` to make it work.
     
     And Also you need to doing flowing `msix_config`
     
     ```yaml
     msix_config:
       display_name: WinToastExample
       toast_activator:
         clsid: "your-notification-activator-guid-2EB1AE5198B7"
         arguments: "-ToastActivated"
         display_name: "YouAppDisplayName"
     ```

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
/// https://docs.microsoft.com/en-us/uwp/api/windows.ui.notifications.toasttemplatetype?view=winrt-20348#fields
enum ToastType {
  imageAndText01,
  imageAndText02,
  imageAndText03,
  imageAndText04,
  text01,
  text02,
  text03,
  text04,
}
// 1, 2, 2, 3, 1, 2, 2, 3

extension ToastTypeExt on ToastType {
  int textFiledCount() {
    return const [1, 2, 2, 3, 1, 2, 2, 3][index];
  }
}

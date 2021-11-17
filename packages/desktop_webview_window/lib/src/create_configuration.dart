class CreateConfiguration {
  final int windowWidth;
  final int windowHeight;

  /// the title of window
  final String title;

  final int titleBarHeight;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.title = "",
    this.titleBarHeight = 40,
  });

  Map toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
        "title": title,
        "titleBarHeight": titleBarHeight,
      };
}

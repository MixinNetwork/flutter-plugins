class CreateConfiguration {
  final int windowWidth;
  final int windowHeight;

  /// the title of window
  final String title;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.title = "",
  });

  Map toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
        "title": title,
      };
}

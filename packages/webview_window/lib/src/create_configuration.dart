class CreateConfiguration {
  final int windowWidth;
  final int windowHeight;

  const CreateConfiguration({
    this.windowWidth = 1280,
    this.windowHeight = 720,
  });

  Map toMap() => {
        "windowWidth": windowWidth,
        "windowHeight": windowHeight,
      };
}

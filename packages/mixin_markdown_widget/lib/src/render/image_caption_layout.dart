import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ImageCaptionLayout extends MultiChildRenderObjectWidget {
  ImageCaptionLayout({
    super.key,
    required Widget image,
    required Widget caption,
    required this.spacing,
  }) : super(children: [image, caption]);

  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderImageCaptionLayout(spacing: spacing);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderImageCaptionLayout renderObject) {
    renderObject.spacing = spacing;
  }
}

class ImageCaptionParentData extends ContainerBoxParentData<RenderBox> {}

class RenderImageCaptionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, ImageCaptionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, ImageCaptionParentData> {
  RenderImageCaptionLayout({required double spacing}) : _spacing = spacing;

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ImageCaptionParentData) {
      child.parentData = ImageCaptionParentData();
    }
  }

  @override
  void performLayout() {
    final image = firstChild;
    final caption = image != null ? childAfter(image) : null;

    if (image == null) {
      size = constraints.smallest;
      return;
    }

    image.layout(constraints, parentUsesSize: true);
    final imageSize = image.size;

    if (caption != null) {
      final captionConstraints = BoxConstraints(maxWidth: imageSize.width);
      caption.layout(captionConstraints, parentUsesSize: true);
      final captionSize = caption.size;

      final captionParentData = caption.parentData as ImageCaptionParentData;
      // Center caption text
      final dx = (imageSize.width - captionSize.width) / 2.0;
      captionParentData.offset = Offset(dx, imageSize.height + spacing);

      size = BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ).constrain(Size(
        imageSize.width,
        imageSize.height + spacing + captionSize.height,
      ));
    } else {
      size = BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ).constrain(imageSize);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

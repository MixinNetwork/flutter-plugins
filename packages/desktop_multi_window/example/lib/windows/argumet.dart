import 'dart:convert';

abstract class WindowArguments {
  const WindowArguments();

  static const String businessIdMain = 'main';
  static const String businessIdVideoPlayer = 'video_player';
  static const String businessIdSample = 'sample';

  factory WindowArguments.fromArguments(String arguments) {
    if (arguments == '') {
      return const MainWindowArguments();
    }
    final json = jsonDecode(arguments) as Map<String, dynamic>;
    final businessId = json['businessId'] as String? ?? '';
    switch (businessId) {
      case businessIdVideoPlayer:
        return VideoPlayerWindowArguments.fromJson(json);
      case businessIdSample:
        return SampleWindowArguments.fromJson(json);
      default:
        throw Exception('Unknown businessId: $businessId');
    }
  }

  Map<String, dynamic> toJson();

  String get businessId;

  String toArguments() => jsonEncode({"businessId": businessId, ...toJson()});

  @override
  String toString() {
    return 'WindowArguments(businessId: $businessId, data: ${toJson()})';
  }
}

class MainWindowArguments extends WindowArguments {
  const MainWindowArguments();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  @override
  String get businessId => WindowArguments.businessIdMain;
}

class VideoPlayerWindowArguments extends WindowArguments {
  const VideoPlayerWindowArguments({required this.videoUrl});

  factory VideoPlayerWindowArguments.fromJson(Map<String, dynamic> json) {
    return VideoPlayerWindowArguments(
      videoUrl: json['videoUrl'] as String? ?? '',
    );
  }

  final String videoUrl;

  @override
  Map<String, dynamic> toJson() {
    return {'videoUrl': videoUrl};
  }

  @override
  String get businessId => WindowArguments.businessIdVideoPlayer;
}

class SampleWindowArguments extends WindowArguments {
  const SampleWindowArguments();

  factory SampleWindowArguments.fromJson(Map<String, dynamic> json) {
    return const SampleWindowArguments();
  }

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  @override
  String get businessId => WindowArguments.businessIdSample;
}

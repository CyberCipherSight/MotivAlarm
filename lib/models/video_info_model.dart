class VideoInfoModel {
  const VideoInfoModel({
    required this.uri,
    required this.durationSeconds,
    required this.valid,
    this.displayWidth = 0,
    this.displayHeight = 0,
    this.errorMessage,
  });

  final String uri;
  final int durationSeconds;
  final bool valid;

  /// Display-space dimensions (rotation already accounted for), so callers
  /// can size a preview box to the clip's exact aspect ratio.
  final int displayWidth;
  final int displayHeight;
  final String? errorMessage;

  /// Falls back to a 16:9 guess if dimensions weren't readable.
  double get aspectRatio =>
      displayWidth > 0 && displayHeight > 0 ? displayWidth / displayHeight : 16 / 9;

  static VideoInfoModel fromJson(Map<String, dynamic> json) {
    return VideoInfoModel(
      uri: json['uri'] as String? ?? '',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      valid: json['valid'] as bool? ?? false,
      displayWidth: json['displayWidth'] as int? ?? 0,
      displayHeight: json['displayHeight'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

class PermissionStatusModel {
  const PermissionStatusModel({
    required this.key,
    required this.title,
    required this.granted,
    required this.reason,
    this.referenceUrl,
  });

  final String key;
  final String title;
  final bool granted;
  final String reason;
  final String? referenceUrl;

  static PermissionStatusModel fromJson(Map<String, dynamic> json) {
    return PermissionStatusModel(
      key: json['key'] as String,
      title: json['title'] as String,
      granted: json['granted'] as bool? ?? false,
      reason: json['reason'] as String,
      referenceUrl: json['referenceUrl'] as String?,
    );
  }
}

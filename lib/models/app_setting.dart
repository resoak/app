class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
  });

  final String key;
  final String value;

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'value': value,
    };
  }

  factory AppSetting.fromMap(Map<String, dynamic> map) {
    return AppSetting(
      key: map['key'] as String? ?? '',
      value: map['value'] as String? ?? '',
    );
  }
}

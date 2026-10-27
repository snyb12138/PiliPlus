class VideoPurifyConfig {
  const VideoPurifyConfig({
    this.keywordPattern = '',
    this.applyToRelatedVideos = true,
    this.exemptFollowedUploaders = true,
  });

  factory VideoPurifyConfig.fromStorage(dynamic raw) {
    if (raw is! Map) return const VideoPurifyConfig();

    final keywordPattern = switch (raw['keywordPattern']) {
      String value => value.trim(),
      _ => '',
    };
    // Validate imported expressions before they replace the active rules.
    final _ = RegExp(keywordPattern, caseSensitive: false);

    return VideoPurifyConfig(
      keywordPattern: keywordPattern,
      applyToRelatedVideos: switch (raw['applyToRelatedVideos']) {
        bool value => value,
        _ => true,
      },
      exemptFollowedUploaders: switch (raw['exemptFollowedUploaders']) {
        bool value => value,
        _ => true,
      },
    );
  }

  final String keywordPattern;
  final bool applyToRelatedVideos;
  final bool exemptFollowedUploaders;

  bool get enabled => keywordPattern.isNotEmpty;

  VideoPurifyConfig copyWith({
    String? keywordPattern,
    bool? applyToRelatedVideos,
    bool? exemptFollowedUploaders,
  }) {
    return VideoPurifyConfig(
      keywordPattern: keywordPattern ?? this.keywordPattern,
      applyToRelatedVideos:
          applyToRelatedVideos ?? this.applyToRelatedVideos,
      exemptFollowedUploaders:
          exemptFollowedUploaders ?? this.exemptFollowedUploaders,
    );
  }

  Map<String, Object> toStorage() => {
    'version': 1,
    'keywordPattern': keywordPattern,
    'applyToRelatedVideos': applyToRelatedVideos,
    'exemptFollowedUploaders': exemptFollowedUploaders,
  };
}

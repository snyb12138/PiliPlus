import 'package:PiliPlus/models/user/reply_ai_filter.dart';

abstract final class PurifyConfigV4 {
  static const String schema = 'piliplus-purify';
  static const int version = 4;
  static const Set<String> _forbiddenKeys = {
    '__proto__',
    'constructor',
    'prototype',
  };

  static Map<String, dynamic> replySection(Map<String, dynamic> root) {
    final nested = root['replyPurify'];
    return nested is Map
        ? sanitizeMap(nested)
        : Map<String, dynamic>.of(root);
  }

  static Map<String, dynamic> sanitizeMap(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || _forbiddenKeys.contains(key)) continue;
      final value = _sanitize(entry.value, 0);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static dynamic _sanitize(dynamic value, int depth) {
    if (depth >= 16) return null;
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double) return value.isFinite ? value : null;
    if (value is Iterable) {
      return value
          .map((item) => _sanitize(item, depth + 1))
          .where((item) => item != null)
          .toList(growable: false);
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String || _forbiddenKeys.contains(key)) continue;
        final item = _sanitize(entry.value, depth + 1);
        if (item != null) result[key] = item;
      }
      return result;
    }
    return null;
  }
}

enum ReplyPurifyCenterMode {
  expanded,
  collapsed,
  hidden;

  factory ReplyPurifyCenterMode.fromStorage(dynamic raw) {
    if (raw is String) {
      return ReplyPurifyCenterMode.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => ReplyPurifyCenterMode.expanded,
      );
    }
    return ReplyPurifyCenterMode.expanded;
  }
}

class ReplyPurifyUser {
  const ReplyPurifyUser({required this.mid, this.name = ''});

  factory ReplyPurifyUser.fromStorage(dynamic raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid reply purify user');
    }
    final rawMid = raw['mid'];
    final mid = switch (rawMid) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };
    if (mid == null || mid <= 0) {
      throw const FormatException('Invalid reply purify uid');
    }
    return ReplyPurifyUser(
      mid: mid,
      name: raw['name'] is String ? (raw['name'] as String).trim() : '',
    );
  }

  final int mid;
  final String name;

  Map<String, Object> toStorage() => {
    'mid': mid,
    if (name.isNotEmpty) 'name': name,
  };
}

class ReplyPurifyConfig {
  ReplyPurifyConfig({
    required Map<int, ReplyPurifyUser> mutedUsers,
    this.aiFilterLevel = ReplyAiFilterLevel.off,
    Map<int, ReplyPurifyUser> trustedAiUsers = const {},
    Map<int, ReplyPurifyUser> markedUsers = const {},
    this.centerMode = ReplyPurifyCenterMode.expanded,
  }) : mutedUsers = Map.unmodifiable(mutedUsers),
       trustedAiUsers = Map.unmodifiable(trustedAiUsers),
       markedUsers = Map.unmodifiable(markedUsers);

  factory ReplyPurifyConfig.defaults() => ReplyPurifyConfig(mutedUsers: {});

  static Map<int, ReplyPurifyUser> _readUsers(dynamic raw) {
    final users = <int, ReplyPurifyUser>{};
    if (raw case final Iterable values) {
      for (final value in values) {
        try {
          final user = ReplyPurifyUser.fromStorage(value);
          users[user.mid] = user;
        } on FormatException {
          // Ignore malformed entries independently.
        }
      }
    }
    return users;
  }

  factory ReplyPurifyConfig.fromStorage(dynamic raw) {
    if (raw is! Map || raw['mutedUsers'] is! Iterable) {
      return ReplyPurifyConfig.defaults();
    }
    return ReplyPurifyConfig(
      mutedUsers: _readUsers(raw['mutedUsers']),
      aiFilterLevel: ReplyAiFilterLevel.fromStorage(raw['aiFilterLevel']),
      trustedAiUsers: _readUsers(raw['trustedAiUsers']),
      markedUsers: _readUsers(raw['markedUsers']),
      centerMode: ReplyPurifyCenterMode.fromStorage(raw['centerMode']),
    );
  }

  final Map<int, ReplyPurifyUser> mutedUsers;
  final ReplyAiFilterLevel aiFilterLevel;
  final Map<int, ReplyPurifyUser> trustedAiUsers;
  final Map<int, ReplyPurifyUser> markedUsers;
  final ReplyPurifyCenterMode centerMode;

  bool contains(int mid) => mutedUsers.containsKey(mid);
  bool trustsAiUser(int mid) => trustedAiUsers.containsKey(mid);
  bool isMarked(int mid) => markedUsers.containsKey(mid);

  ReplyPurifyConfig addUser(int mid, {String name = ''}) {
    if (mid <= 0) return this;
    final users = Map<int, ReplyPurifyUser>.of(mutedUsers);
    users[mid] = ReplyPurifyUser(mid: mid, name: name.trim());
    return copyWith(mutedUsers: users);
  }

  ReplyPurifyConfig removeUser(int mid) {
    if (!mutedUsers.containsKey(mid)) return this;
    final users = Map<int, ReplyPurifyUser>.of(mutedUsers)..remove(mid);
    return copyWith(mutedUsers: users);
  }

  ReplyPurifyConfig markUser(int mid, {String name = ''}) {
    if (mid <= 0) return this;
    final users = Map<int, ReplyPurifyUser>.of(markedUsers);
    users[mid] = ReplyPurifyUser(mid: mid, name: name.trim());
    return copyWith(markedUsers: users);
  }

  ReplyPurifyConfig unmarkUser(int mid) {
    if (!markedUsers.containsKey(mid)) return this;
    final users = Map<int, ReplyPurifyUser>.of(markedUsers)..remove(mid);
    return copyWith(markedUsers: users);
  }

  ReplyPurifyConfig setAiFilterLevel(ReplyAiFilterLevel level) =>
      copyWith(aiFilterLevel: level);

  ReplyPurifyConfig setCenterMode(ReplyPurifyCenterMode mode) =>
      copyWith(centerMode: mode);

  ReplyPurifyConfig trustAiUser(int mid, {String name = ''}) {
    if (mid <= 0) return this;
    final users = Map<int, ReplyPurifyUser>.of(trustedAiUsers);
    users[mid] = ReplyPurifyUser(mid: mid, name: name.trim());
    return copyWith(trustedAiUsers: users);
  }

  ReplyPurifyConfig untrustAiUser(int mid) {
    if (!trustedAiUsers.containsKey(mid)) return this;
    final users = Map<int, ReplyPurifyUser>.of(trustedAiUsers)..remove(mid);
    return copyWith(trustedAiUsers: users);
  }

  ReplyPurifyConfig copyWith({
    Map<int, ReplyPurifyUser>? mutedUsers,
    ReplyAiFilterLevel? aiFilterLevel,
    Map<int, ReplyPurifyUser>? trustedAiUsers,
    Map<int, ReplyPurifyUser>? markedUsers,
    ReplyPurifyCenterMode? centerMode,
  }) {
    return ReplyPurifyConfig(
      mutedUsers: mutedUsers ?? this.mutedUsers,
      aiFilterLevel: aiFilterLevel ?? this.aiFilterLevel,
      trustedAiUsers: trustedAiUsers ?? this.trustedAiUsers,
      markedUsers: markedUsers ?? this.markedUsers,
      centerMode: centerMode ?? this.centerMode,
    );
  }

  Map<String, Object> toStorage() => {
    'version': 3,
    'mutedUsers': mutedUsers.values.map((e) => e.toStorage()).toList(),
    'aiFilterLevel': aiFilterLevel.name,
    'trustedAiUsers': trustedAiUsers.values.map((e) => e.toStorage()).toList(),
    'markedUsers': markedUsers.values.map((e) => e.toStorage()).toList(),
    'centerMode': centerMode.name,
  };
}

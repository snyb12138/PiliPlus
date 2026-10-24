import 'package:PiliPlus/models/user/reply_ai_filter.dart';

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
  }) : mutedUsers = Map.unmodifiable(mutedUsers),
       trustedAiUsers = Map.unmodifiable(trustedAiUsers);

  factory ReplyPurifyConfig.defaults() => ReplyPurifyConfig(mutedUsers: {});

  factory ReplyPurifyConfig.fromStorage(dynamic raw) {
    if (raw is! Map || raw['mutedUsers'] is! Iterable) {
      return ReplyPurifyConfig.defaults();
    }

    final users = <int, ReplyPurifyUser>{};
    for (final value in raw['mutedUsers'] as Iterable) {
      try {
        final user = ReplyPurifyUser.fromStorage(value);
        users[user.mid] = user;
      } on FormatException {
        // Ignore malformed entries instead of disabling the whole local list.
      }
    }
    final trustedUsers = <int, ReplyPurifyUser>{};
    if (raw['trustedAiUsers'] case final Iterable values) {
      for (final value in values) {
        try {
          final user = ReplyPurifyUser.fromStorage(value);
          trustedUsers[user.mid] = user;
        } on FormatException {
          // Ignore malformed entries independently from the muted list.
        }
      }
    }
    return ReplyPurifyConfig(
      mutedUsers: users,
      aiFilterLevel: ReplyAiFilterLevel.fromStorage(raw['aiFilterLevel']),
      trustedAiUsers: trustedUsers,
    );
  }

  final Map<int, ReplyPurifyUser> mutedUsers;
  final ReplyAiFilterLevel aiFilterLevel;
  final Map<int, ReplyPurifyUser> trustedAiUsers;

  bool contains(int mid) => mutedUsers.containsKey(mid);
  bool trustsAiUser(int mid) => trustedAiUsers.containsKey(mid);

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

  ReplyPurifyConfig setAiFilterLevel(ReplyAiFilterLevel level) =>
      copyWith(aiFilterLevel: level);

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
  }) {
    return ReplyPurifyConfig(
      mutedUsers: mutedUsers ?? this.mutedUsers,
      aiFilterLevel: aiFilterLevel ?? this.aiFilterLevel,
      trustedAiUsers: trustedAiUsers ?? this.trustedAiUsers,
    );
  }

  Map<String, Object> toStorage() => {
    'version': 2,
    'mutedUsers': mutedUsers.values.map((e) => e.toStorage()).toList(),
    'aiFilterLevel': aiFilterLevel.name,
    'trustedAiUsers': trustedAiUsers.values.map((e) => e.toStorage()).toList(),
  };
}

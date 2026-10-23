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
  ReplyPurifyConfig({required Map<int, ReplyPurifyUser> mutedUsers})
    : mutedUsers = Map.unmodifiable(mutedUsers);

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
    return ReplyPurifyConfig(mutedUsers: users);
  }

  final Map<int, ReplyPurifyUser> mutedUsers;

  bool contains(int mid) => mutedUsers.containsKey(mid);

  ReplyPurifyConfig addUser(int mid, {String name = ''}) {
    if (mid <= 0) return this;
    final users = Map<int, ReplyPurifyUser>.of(mutedUsers);
    users[mid] = ReplyPurifyUser(mid: mid, name: name.trim());
    return ReplyPurifyConfig(mutedUsers: users);
  }

  ReplyPurifyConfig removeUser(int mid) {
    if (!mutedUsers.containsKey(mid)) return this;
    final users = Map<int, ReplyPurifyUser>.of(mutedUsers)..remove(mid);
    return ReplyPurifyConfig(mutedUsers: users);
  }

  Map<String, Object> toStorage() => {
    'version': 1,
    'mutedUsers': mutedUsers.values.map((e) => e.toStorage()).toList(),
  };
}

class AppUser {
  final int id;
  final String email;
  final String username;
  final String token;

  AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.token,
  });

  factory AppUser.fromJson(Map<String, dynamic> json, String token) {
    return AppUser(
      id: json['user_id'] ?? json['id'] ?? 0,
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      token: token,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'token': token,
    };
  }
}

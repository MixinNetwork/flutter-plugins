class WebviewCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime expires;
  final bool secure;
  final bool httpOnly;
  final bool sessionOnly;

  WebviewCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
    required this.sessionOnly,
  });

  factory WebviewCookie.fromJson(Map<String, dynamic> json) {
    return WebviewCookie(
      name: json['name'],
      value: json['value'],
      domain: json['domain'],
      expires: DateTime.parse(json['expires']),
      httpOnly: json['httpOnly'],
      path: json['path'],
      secure: json['secure'],
      sessionOnly: json['sessionOnly'],
    );
  }
}

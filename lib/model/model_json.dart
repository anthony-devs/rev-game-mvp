/// Shared helpers for reading and writing model data.
///
/// Every model has two shapes:
///  - `toJson` / `fromJson`: plain JSON (dates as milliseconds). Use for the cache
///    (SharedPreferences, Hive, Isar) and for anything that must be encodable.
///  - `toFirestore` / `fromFirestore`: what goes to and from Cloud Firestore.
///    Dates are `DateTime` (the SDK turns them into Timestamps), and the document id
///    is passed in separately.
///
/// The models do not import Firebase, so they work before the SDK is added.
typedef Json = Map<String, dynamic>;

/// Reads a date from milliseconds, an ISO string, a DateTime, or a Firestore Timestamp.
DateTime? parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  try {
    // Firestore Timestamp has toDate(). Called dynamically so this file needs no Firebase import.
    final d = (value as dynamic).toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

int? dateToMs(DateTime? date) => date?.millisecondsSinceEpoch;

double parseDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int parseInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool parseBool(Object? value, [bool fallback = false]) => value is bool ? value : fallback;

String? parseString(Object? value) {
  if (value == null) return null;
  final s = value.toString();
  return s.isEmpty ? null : s;
}

/// Finds an enum value by its name. Unknown or missing names return [fallback],
/// so a new value added on the server never crashes an older app.
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Casts to a string-keyed map, or returns an empty one.
Json parseMap(Object? value) {
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_utils.dart';

/// Mirrors `User` in frontend/src/types/index.ts (Firestore `users/{uid}`).
class UserProfile {
  final String id;
  final Map<String, dynamic> data;
  const UserProfile(this.id, this.data);

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserProfile(doc.id, {...?doc.data()});

  String get nick => safeStr(data['nick']);
  String get fotoUrl => safeStr(data['fotoUrl']);
  int? get edad => data['edad'] is num ? (data['edad'] as num).toInt() : null;
  String? get fechaNacimiento => data['fechaNacimiento'] as String?;
  String get rol => safeStr(data['rol']);
  String get intencion => safeStr(data['intencion']);
  String? get mood => data['mood'] as String?;
  String get bio => safeStr(data['bio']);
  String? get cityId => data['cityId'] as String?;
  String? get role => data['role'] as String?;
  bool get online => data['online'] == true;
  bool get verified => data['verified'] == true;
  String? get verificationStatus => data['verificationStatus'] as String?;
  bool get ghostMode => data['ghostMode'] == true;
  bool get cruisingMode => data['cruisingMode'] == true;
  bool get nsfwBlur => data['nsfwBlur'] != false;
  bool get notificationsEnabled => data['notificationsEnabled'] == true;
  bool get needsUpdate => data['needsUpdate'] == true;
  List<String> get extraPhotos => asStringList(data['extraPhotos']);
  List<String> get privatePhotos => asStringList(data['privatePhotos']);
  List<String> get intereses => asStringList(data['intereses']);
  List<String> get matches => asStringList(data['matches']);
  int? get altura => data['altura'] is num ? (data['altura'] as num).toInt() : null;
  int? get peso => data['peso'] is num ? (data['peso'] as num).toInt() : null;
  double? get lat => asDouble(data['lat']);
  double? get lng => asDouble(data['lng']);
  String get membershipTier => (data['membershipTier'] as String?) ?? 'free';
  String? get membershipStatus => data['membershipStatus'] as String?;
  bool get promoMember => data['promoMember'] == true;
  DateTime? get blackBoostExpires => parseDate(data['blackBoostExpires']);
  String? get loginUsername => data['loginUsername'] as String?;
  bool get hasLoginCredentials => data['hasLoginCredentials'] == true;
  DateTime? get createdAt => parseDate(data['createdAt'] ?? data['created_at']);

  bool get incomplete => fotoUrl.isEmpty || nick.isEmpty;
}

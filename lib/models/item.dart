import 'dart:convert';

class Item {
  final String id;
  final String? name;
  final String? type;
  final String? collectionType;
  final Map<String, dynamic>? userData;
  final String? parentId;
  final double? primaryImageAspectRatio;
  final String? sortName;
  final Map<String, dynamic> rawJson;

  Item({
    required this.id,
    this.name,
    this.type,
    this.collectionType,
    this.userData,
    this.parentId,
    this.primaryImageAspectRatio,
    this.sortName,
    required this.rawJson,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    final userData = json['UserData'];
    return Item(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String?,
      type: json['Type'] as String?,
      collectionType: json['CollectionType'] as String?,
      userData: userData is Map<String, dynamic> ? userData : null,
      parentId: json['ParentId'] as String?,
      primaryImageAspectRatio: (json['PrimaryImageAspectRatio'] is num)
          ? (json['PrimaryImageAspectRatio'] as num).toDouble()
          : null,
      sortName: json['SortName'] as String?,
      rawJson: json,
    );
  }

  Map<String, dynamic> toJson() {
    return rawJson;
  }

  Map<String, dynamic> toDbMap(String category) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'collectionType': collectionType,
      'parentId': parentId,
      'category': category,
      'json': jsonEncode(rawJson),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory Item.fromDbMap(Map<String, dynamic> map) {
    final json = jsonDecode(map['json'] as String);
    return Item.fromJson(json as Map<String, dynamic>);
  }
}

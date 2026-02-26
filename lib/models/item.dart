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
    return Item(
      id: json['Id'] ?? '',
      name: json['Name'],
      type: json['Type'],
      collectionType: json['CollectionType'],
      userData: json['UserData'],
      parentId: json['ParentId'],
      primaryImageAspectRatio: (json['PrimaryImageAspectRatio'] is num)
          ? json['PrimaryImageAspectRatio'].toDouble()
          : null,
      sortName: json['SortName'],
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
    return Item.fromJson(jsonDecode(map['json']));
  }
}

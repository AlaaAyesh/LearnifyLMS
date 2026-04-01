import '../../domain/entities/reel.dart';
import 'reel_category_model.dart';
import 'reel_owner_model.dart';

class ReelModel extends Reel {
  const ReelModel({
    required super.id,
    required super.title,
    required super.description,
    required super.redirectType,
    required super.redirectLink,
    required super.thumbnailUrl,
    required super.bunnyUrl,
    super.durationSeconds,
    required super.likesCount,
    required super.viewsCount,
    required super.owner,
    super.categories,
    required super.viewed,
    required super.liked,
    required super.createdAt,
    required super.updatedAt,
  });

  factory ReelModel.fromJson(Map<String, dynamic> json) {
    return ReelModel(
      id: _parseInt(json['id']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      redirectType: json['redirect_type']?.toString() ?? '',
      redirectLink: json['redirect_link']?.toString() ?? '',
      thumbnailUrl: _parseThumbnailUrl(json),
      bunnyUrl: json['bunny_url']?.toString() ?? '',
      durationSeconds: _parseInt(json['duration_seconds']),
      likesCount: _parseInt(json['likes_count']),
      viewsCount: _parseInt(json['views_count']),
      owner: json['owner'] != null && json['owner'] is Map
          ? ReelOwnerModel.fromJson(json['owner'])
          : const ReelOwnerModel(id: 0, name: '', email: ''),
      categories: json['categories'] != null && json['categories'] is List
          ? (json['categories'] as List)
          .map((c) => ReelCategoryModel.fromJson(c as Map<String, dynamic>))
          .toList()
          : [],
      viewed: _parseBool(json['viewed']),
      liked: _parseBool(json['liked']),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'redirect_type': redirectType,
      'redirect_link': redirectLink,
      'thumbnail_url': thumbnailUrl,
      'bunny_url': bunnyUrl,
      'duration_seconds': durationSeconds,
      'likes_count': likesCount,
      'views_count': viewsCount,
      'owner': (owner as ReelOwnerModel).toJson(),
      'categories': categories.map((c) => (c as ReelCategoryModel).toJson()).toList(),
      'viewed': viewed,
      'liked': liked,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  static String _parseThumbnailUrl(Map<String, dynamic> json) {
    final candidates = [
      json['thumbnail_url'],
      json['thumbnailUrl'],
      json['thumbnail'],
      json['poster_url'],
      json['image'],
    ];

    for (final candidate in candidates) {
      if (candidate == null) continue;

      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }

      if (candidate is Map<String, dynamic>) {
        final nested = candidate['url']?.toString();
        if (nested != null && nested.trim().isNotEmpty) {
          return nested.trim();
        }
      }
    }

    return '';
  }
}




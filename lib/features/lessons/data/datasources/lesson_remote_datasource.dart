import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../home/data/models/lesson_model.dart';

abstract class LessonRemoteDataSource {
  Future<LessonModel> getLessonById(int id);

  Future<void> markLessonAsViewed(int id);
}

class LessonRemoteDataSourceImpl implements LessonRemoteDataSource {
  final DioClient dioClient;

  LessonRemoteDataSourceImpl(this.dioClient);

  @override
  Future<LessonModel> getLessonById(int id) async {
    try {
      final response = await dioClient.get('${ApiConstants.lessons}/$id');

      if (response.statusCode == 200) {
        final responseData = response.data;
        Map<String, dynamic> lessonData;

        if (responseData['data'] is Map) {
          lessonData = responseData['data'];
        } else if (responseData['lesson'] is Map) {
          lessonData = responseData['lesson'];
        } else {
          lessonData = responseData;
        }

        return LessonModel.fromJson(lessonData);
      }

      throw ServerException(
        message: response.data['message'] ?? 'فشل في جلب الدرس',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'فشل في جلب الدرس');
    }
  }

  @override
  Future<void> markLessonAsViewed(int id) async {
    try {
      if (kDebugMode) {
        debugPrint('LessonRemoteDataSource: Marking lesson $id as viewed');
      }
      final response = await dioClient.post(
        '${ApiConstants.lessons}/$id/view',
      );

      if (kDebugMode) {
        debugPrint('LessonRemoteDataSource: Response status: ${response.statusCode}');
        debugPrint('LessonRemoteDataSource: Response data: ${response.data}');
      }

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw ServerException(
          message: response.data['message'] ?? 'فشل في تحديث حالة المشاهدة',
          statusCode: response.statusCode,
        );
      }
      if (kDebugMode) {
        debugPrint('LessonRemoteDataSource: Successfully marked lesson $id as viewed');
      }
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('LessonRemoteDataSource: Error marking lesson $id as viewed: ${e.message}');
        debugPrint('LessonRemoteDataSource: Error response: ${e.response?.data}');
      }
      throw _handleDioError(e, 'فشل في تحديث حالة المشاهدة');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LessonRemoteDataSource: Unexpected error: $e');
      }
      rethrow;
    }
  }

  ServerException _handleDioError(DioException e, String defaultMessage) {
    String errorMessage = defaultMessage;

    if (e.response?.statusCode == 401) {
      errorMessage = 'يجب تسجيل الدخول أولاً';
    } else if (e.response?.statusCode == 403) {
      errorMessage = e.response?.data['message'] ?? 'غير مصرح لك بمشاهدة هذا الدرس';
    } else if (e.response?.statusCode == 404) {
      errorMessage = e.response?.data['message'] ?? 'الدرس غير موجود';
    } else if (e.response?.data != null && e.response?.data['message'] != null) {
      errorMessage = e.response?.data['message'];
    }

    return ServerException(
      message: errorMessage,
      statusCode: e.response?.statusCode,
    );
  }
}




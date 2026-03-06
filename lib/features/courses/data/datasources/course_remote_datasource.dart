import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../home/data/models/course_model.dart';

List<CourseModel> parseCoursesListInIsolate(List<dynamic> jsonList) {
  return jsonList.map((json) => CourseModel.fromJson(json)).toList();
}

abstract class CourseRemoteDataSource {
  Future<List<CourseModel>> getCourses({
    int? page,
    int? perPage,
    int? categoryId,
    int? specialtyId,
  });

  Future<CourseModel> getCourseById(int id);

  Future<List<CourseModel>> getMyCourses();
}

class CourseRemoteDataSourceImpl implements CourseRemoteDataSource {
  final DioClient dioClient;

  CourseRemoteDataSourceImpl(this.dioClient);

  @override
  Future<List<CourseModel>> getCourses({
    int? page,
    int? perPage,
    int? categoryId,
    int? specialtyId,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (page != null) queryParams['page'] = page;
      if (perPage != null) queryParams['per_page'] = perPage;

      final searchParts = <String>[];
      if (categoryId != null) {
        searchParts.add('categories.category_id:$categoryId');
      }
      if (specialtyId != null) {
        searchParts.add('specialty_id:$specialtyId');
      }
      
      if (searchParts.isNotEmpty) {
        queryParams['search'] = searchParts.join(';');
      }

      final response = await dioClient.get(
        ApiConstants.courses,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
        cancelTag: 'courses_${categoryId}_${specialtyId}_$page',
      );

      if (response.statusCode == 200) {
        List<dynamic> coursesJson;
        final responseData = response.data;

        if (responseData['data'] is Map && responseData['data']['data'] is List) {
          coursesJson = responseData['data']['data'];
        } else if (responseData['data'] is List) {
          coursesJson = responseData['data'];
        } else if (responseData['courses'] is List) {
          coursesJson = responseData['courses'];
        } else if (responseData is List) {
          coursesJson = responseData;
        } else {
          coursesJson = [];
        }

        if (coursesJson.isEmpty) return <CourseModel>[];
        return compute(parseCoursesListInIsolate, coursesJson);
      }

      throw ServerException(
        message: response.data['message'] ?? 'فشل في جلب الكورسات',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'فشل في جلب الكورسات');
    }
  }

  @override
  Future<CourseModel> getCourseById(int id) async {
    try {
      final response = await dioClient.get('${ApiConstants.courses}/$id');

      if (response.statusCode == 200) {
        final responseData = response.data;
        Map<String, dynamic> courseData;

        if (responseData['data'] is Map && responseData['data']['data'] is Map) {
          courseData = responseData['data']['data'];
        } else if (responseData['data'] is Map) {
          courseData = responseData['data'];
        } else if (responseData['course'] is Map) {
          courseData = responseData['course'];
        } else {
          courseData = responseData;
        }

        return CourseModel.fromJson(courseData);
      }

      throw ServerException(
        message: response.data['message'] ?? 'فشل في جلب الكورس',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'فشل في جلب الكورس');
    }
  }

  @override
  Future<List<CourseModel>> getMyCourses() async {
    try {
      final response = await dioClient.get(ApiConstants.myCourses);

      if (response.statusCode == 200) {
        List<dynamic> coursesJson;
        final responseData = response.data;

        if (responseData['data'] is Map && responseData['data']['data'] is List) {
          coursesJson = responseData['data']['data'];
        } else if (responseData['data'] is List) {
          coursesJson = responseData['data'];
        } else if (responseData['courses'] is List) {
          coursesJson = responseData['courses'];
        } else if (responseData is List) {
          coursesJson = responseData;
        } else {
          coursesJson = [];
        }

        if (coursesJson.isEmpty) return <CourseModel>[];
        return compute(parseCoursesListInIsolate, coursesJson);
      }

      throw ServerException(
        message: response.data['message'] ?? 'فشل في جلب كورساتي',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e, 'فشل في جلب كورساتي');
    }
  }

  ServerException _handleDioError(DioException e, String defaultMessage) {
    String errorMessage = defaultMessage;

    if (e.response?.statusCode == 401) {
      errorMessage = 'يجب تسجيل الدخول أولاً';
    } else if (e.response?.statusCode == 403) {
      errorMessage = e.response?.data['message'] ?? 'غير مصرح لك بهذا الإجراء';
    } else if (e.response?.statusCode == 404) {
      errorMessage = e.response?.data['message'] ?? 'الكورس غير موجود';
    } else if (e.response?.data != null && e.response?.data['message'] != null) {
      errorMessage = e.response?.data['message'];
    }

    return ServerException(
      message: errorMessage,
      statusCode: e.response?.statusCode,
    );
  }
}





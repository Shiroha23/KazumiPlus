import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/utils/dandan_credentials.dart';
import 'package:kazumi/utils/http_headers.dart';
import 'package:kazumi/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    if (!hasDandanCredentials) {
      throw const NetworkException(
        type: NetworkExceptionType.unknown,
        message: '当前构建未配置弹幕服务凭据',
      );
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uri = Uri.parse(url);
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      'X-Auth': 1,
      'X-AppId': dandanCredentials['id'],
      'X-Timestamp': timestamp,
      'X-Signature': generateDandanSignature(uri.path, timestamp),
      ...headers,
    };

    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw NetworkException(
          type: NetworkExceptionType.badResponse,
          message: '弹幕服务拒绝访问（HTTP $status），请检查应用凭据或访问限制',
          statusCode: status,
          rawError: e,
          stackTrace: e.stackTrace,
        );
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}

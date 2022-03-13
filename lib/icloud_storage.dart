import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

/// A function-type alias takes a stream as argument and returns void
typedef StreamHandler<T> = void Function(Stream<T>);

/// The main class for the plugin. Contains all the API's needed for listing,
/// uploading, downloading and deleting files.
class ICloudStorage {
  ICloudStorage._();
  static final ICloudStorage _instance = ICloudStorage._();
  static const MethodChannel _channel = MethodChannel('icloud_storage');

  /// Get an instance of the ICloudStorage class
  ///
  /// [containerId] is the iCloud Container ID created in the apple developer
  /// account
  ///
  /// Returns a future completing with an instance of the ICloudStorage class
  static Future<ICloudStorage> getInstance(String containerId) async {
    await _channel.invokeMethod('initialize', {'containerId': containerId});
    return _instance;
  }

  Future<bool> isAvailable() async {
    return await _channel.invokeMethod('isAvailable');
  }

  /// Lists files from the iCloud container directory, which lives on the device
  ///
  /// Returns a future completing with a list of file names
  Future<List<String>> listFiles({String? directory}) async {
    final files = await _channel.invokeListMethod<String>('listFiles', {'eventChannelName': '', 'directory': directory});
    return files ?? [];
  }

  Future<List<String>> subFiles({String? directory}) async {
    final files = await _channel.invokeListMethod<String>('subFiles', {'directory': directory});
    return files ?? [];
  }

  /// Lists files from the iCloud container directory, which lives on the
  /// device. Also watches for updates.
  ///
  /// Returns a future completing with a stream of lists of the file names
  Future<Stream<List<String>>> watchFiles({String? directory}) async {
    const eventChannelName = 'icloud_storage/event/list';
    await _channel.invokeMethod('createEventChannel', {'eventChannelName': eventChannelName, 'directory': directory});
    const watchFileEventChannel = EventChannel(eventChannelName);
    _channel.invokeMethod('listFiles', {'eventChannelName': eventChannelName});
    return watchFileEventChannel
        .receiveBroadcastStream()
        .where((event) => event is List)
        .map<List<String>>((event) => (event as List).map((item) => item as String).toList());
  }

  /// Start to upload a file from a local path to iCloud
  ///
  /// [filePath] is the full path of the local file
  ///
  /// [destinationFileName] is the name of the file you want to store in iCloud.
  /// If not specified, the name of the local file is used.
  ///
  /// [onProgress] is an optional callback to to track the progress of the
  /// upload. It takes a Stream<double> as input, which is the percentage of
  /// the data being uploaded.
  ///
  /// The returned future completes without waiting for the file to be uploaded
  /// to iCloud
  Future<void> startUpload({
    required String filePath,
    String? directory,
    String? destinationFileName,
    StreamHandler<double>? onProgress,
  }) async {
    if (filePath.trim().isEmpty) {
      throw InvalidArgumentException('invalid filePath');
    }

    final cloudFileName = destinationFileName ?? filePath.split('/').last;
    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = 'icloud_storage/event/upload/$cloudFileName${_getChannelNameSuffix()}';
      await _channel.invokeMethod('createEventChannel', {'eventChannelName': eventChannelName, 'directory': directory});
      final uploadEventChannel = EventChannel(eventChannelName);
      final stream = uploadEventChannel.receiveBroadcastStream().where((event) => event is double).map((event) => event as double);
      onProgress(stream);
    }

    await _channel.invokeMethod('upload', {
      'localFilePath': filePath,
      'cloudFileName': cloudFileName,
      'eventChannelName': eventChannelName,
      'directory': directory,
    });
  }

  /// Start to download a file from iCloud
  ///
  /// [fileName] is the name of the file on iCloud
  ///
  /// [destinationFilePath] is the full path of the local file you want the
  /// iCloud file to be saved as
  ///
  /// [onProgress] is an optional callback to to track the progress of the
  /// download. It takes a Stream<double> as input, which is the percentage of
  /// the data being downloaded.
  ///
  /// The returned future completes without waiting for the file to be
  /// downloaded
  Future<void> startDownload({
    required String fileName,
    String? directory,
    required String destinationFilePath,
    StreamHandler<double>? onProgress,
  }) async {
    if (fileName.trim().isEmpty || fileName.contains('/')) {
      throw InvalidArgumentException('invalid fileName');
    }
    if (destinationFilePath.trim().isEmpty || destinationFilePath[destinationFilePath.length - 1] == '/') {
      throw InvalidArgumentException('invalid destinationFilePath');
    }

    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = 'icloud_storage/event/download/$fileName${_getChannelNameSuffix()}';
      await _channel.invokeMethod('createEventChannel', {'eventChannelName': eventChannelName, 'directory': directory});
      final downloadEventChannel = EventChannel(eventChannelName);
      final stream = downloadEventChannel.receiveBroadcastStream().where((event) => event is double).map((event) => event as double);
      onProgress(stream);
    }

    await _channel.invokeMethod('download', {
      'cloudFileName': fileName,
      'localFilePath': destinationFilePath,
      'eventChannelName': eventChannelName,
      'directory': directory,
    });
  }

  /// Delete a file from iCloud container directory, which lives on the device
  ///
  /// [fileName] is the name of the file on iCloud
  ///
  /// The returned future completes without waiting for the file to be deleted
  /// on iCloud
  Future<void> delete({
    required String fileName,
    String? directory,
    StreamHandler<double>? onProgress,
  }) async {
    if (fileName.trim().isEmpty || fileName.contains('/')) {
      throw InvalidArgumentException('invalid fileName');
    }

    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = 'icloud_storage/event/delete/$fileName${_getChannelNameSuffix()}';
      await _channel.invokeMethod('createEventChannel', {'eventChannelName': eventChannelName, 'directory': directory});
      final deleteEventChannel = EventChannel(eventChannelName);
      final stream = deleteEventChannel.receiveBroadcastStream().where((event) => event is double).map((event) => event as double);
      onProgress(stream);
    }

    await _channel.invokeMethod('delete', {
      'cloudFileName': fileName,
      'eventChannelName': eventChannelName,
      'directory': directory,
    });
  }

  Future<void> deleteList({
    required List<String> fileNameList,
    String? directory,
    StreamHandler<double>? onProgress,
  }) async {
    if (fileNameList.isEmpty) return;

    var eventChannelName = '';

    if (onProgress != null) {
      eventChannelName = 'icloud_storage/event/deleteList/$fileNameList${_getChannelNameSuffix()}';
      await _channel.invokeMethod('createEventChannel', {'eventChannelName': eventChannelName, 'directory': directory});
      final deleteEventChannel = EventChannel(eventChannelName);
      final stream = deleteEventChannel.receiveBroadcastStream().where((event) => event is double).map((event) => event as double);
      onProgress(stream);
    }
    await _channel.invokeMethod("deleteList", {
      'cloudFileNameList': fileNameList,
      'eventChannelName': eventChannelName,
      'directory': directory,
    });
  }

  String _getChannelNameSuffix() => '-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999)}';
}

/// An exception class used for development. It's ued when invalid argument
/// is passed to the API
class InvalidArgumentException implements Exception {
  final String _message;

  /// Constructor takes the exception message as an argument
  InvalidArgumentException(this._message);

  @override
  String toString() => "InvalidArgumentException: $_message";
}

/// A class contains the error code from PlatformException
class PlatformExceptionCode {
  /// The code indicates iCloud container ID is not valid, or user is not signed
  /// in to iCloud, or user denied iCloud permission for this app
  static const String iCloudConnectionOrPermission = 'E_CTR';

  /// The code indicates other error from native code
  static const String nativeCodeError = 'E_NAT';
}

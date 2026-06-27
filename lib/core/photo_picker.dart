import 'dart:io';
import 'package:flutter/services.dart';

class PhotoPickerHelper {
  static const platform = MethodChannel('com.twalitso.padue/photo_picker');

  // Pick a single photo
  static Future<File?> pickPhoto() async {
    try {
      final String? path = await platform.invokeMethod('pickPhoto');
      return path != null ? File(path) : null;
    } on PlatformException catch (e) {
      return null;
    }
  }

  // Pick a single document
  static Future<File?> pickDocument() async {
    try {
      final String? path = await platform.invokeMethod('pickDocument');
      return path != null ? File(path) : null;
    } on PlatformException catch (e) {
      return null;
    }
  }

  // Pick single or multiple photos
  static Future<List<File>?> pickPhotos({bool allowMultiple = true}) async {
    try {
      final result = await platform.invokeMethod('pickPhotos', {'allowMultiple': allowMultiple});
      if (result == null) return null;
      if (result is String) return [File(result)]; // Single file
      if (result is List<dynamic>) {
        return result.cast<String>().map((path) => File(path)).toList();
      }
      return null;
    } on PlatformException catch (e) {
      return null;
    }
  }
}
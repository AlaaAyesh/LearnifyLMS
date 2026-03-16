import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'app.dart';
import 'core/di/injection_container.dart';
import 'core/storage/hive_service.dart';
import 'core/network/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    HiveService.init(),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]),
    _setSystemUI(),
  ]);

  await Future.wait([CacheService.init(), initDependencies()]);

  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  runApp(const LearnifyApp());
}

Future<void> _setSystemUI() async {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
}



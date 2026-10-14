import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Env.validateProductionUrl(environment: kReleaseMode ? 'prod' : Env.flavor);
  runApp(const ProviderScope(child: TopCoffeeApp()));
}

import 'package:flutter/material.dart';

import 'app_routes.dart';

/// Shared navigator observer used by the voice layer and dashboard screens.
/// Keeping it outside app.dart avoids a circular web import during compilation.
class AppRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  final ValueNotifier<String?> currentRoute = ValueNotifier<String?>(
    AppRoutes.login,
  );

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) currentRoute.value = route.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute?.settings.name != null) {
      currentRoute.value = newRoute!.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute?.settings.name != null) {
      currentRoute.value = previousRoute!.settings.name;
    }
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();

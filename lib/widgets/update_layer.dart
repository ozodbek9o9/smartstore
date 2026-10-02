import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'update_dialog.dart';

class UpdateServiceScope extends InheritedNotifier<UpdateService> {
  const UpdateServiceScope({
    super.key,
    required UpdateService service,
    required super.child,
  }) : super(notifier: service);

  static UpdateService of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<UpdateServiceScope>();
    assert(scope != null, 'UpdateServiceScope is missing above this context.');
    return scope!.notifier!;
  }
}

class UpdateLayer extends StatefulWidget {
  const UpdateLayer({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<UpdateLayer> createState() => _UpdateLayerState();
}

class _UpdateLayerState extends State<UpdateLayer> {
  late final UpdateService _service;
  String? _promptedVersion;
  bool _dialogOpen = false;
  bool _dialogScheduled = false;

  @override
  void initState() {
    super.initState();
    _service = UpdateService()..addListener(_showAvailableUpdate);
    _service.start();
  }

  void _showAvailableUpdate() {
    final update = _service.update;
    if (!_service.startupComplete ||
        update == null ||
        _dialogOpen ||
        _dialogScheduled ||
        _promptedVersion == update.version) {
      return;
    }

    _dialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogScheduled = false;
      if (!mounted || _service.update == null || _dialogOpen) return;
      final navigatorContext =
          widget.navigatorKey.currentState?.overlay?.context;
      if (navigatorContext == null) return;

      final candidate = _service.update!;
      _promptedVersion = candidate.version;
      _dialogOpen = true;
      unawaited(
        showUpdateDialog(
          context: navigatorContext,
          service: _service,
          currentVersion: UpdateService.currentAppVersion,
        ).whenComplete(() => _dialogOpen = false),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _service.removeListener(_showAvailableUpdate);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UpdateServiceScope(service: _service, child: widget.child);
}

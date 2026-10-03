import 'package:flutter/material.dart';

import '../services/update_service.dart';

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
  const UpdateLayer({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateLayer> createState() => _UpdateLayerState();
}

class _UpdateLayerState extends State<UpdateLayer> {
  late final UpdateService _service = UpdateService();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UpdateServiceScope(service: _service, child: widget.child);
}

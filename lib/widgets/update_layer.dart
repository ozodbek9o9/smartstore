import 'package:flutter/material.dart';

import '../models/update_info.dart';
import '../services/update_service.dart';

class UpdateLayer extends StatefulWidget {
  const UpdateLayer({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateLayer> createState() => _UpdateLayerState();
}

class _UpdateLayerState extends State<UpdateLayer> {
  late final UpdateService _service;

  @override
  void initState() {
    super.initState();
    _service = UpdateService()..start();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final isBlocking = _service.isUpdating;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_service.update != null && !isBlocking)
              Positioned(
                top: 16,
                right: 16,
                child: _UpdateReminder(
                  update: _service.update!,
                  failed: _service.status == UpdateStatus.failed,
                  onUpdate: _service.install,
                  onRetry: () => _service.install(),
                  onDismiss: () => setState(() => _service.update = null),
                ),
              ),
            if (isBlocking)
              _UpdateOverlay(
                status: _service.status,
                progress: _service.progress,
              ),
          ],
        );
      },
    );
  }
}

class _UpdateReminder extends StatelessWidget {
  const _UpdateReminder({
    required this.update,
    required this.failed,
    required this.onUpdate,
    required this.onRetry,
    required this.onDismiss,
  });

  final UpdateInfo update;
  final bool failed;
  final VoidCallback onUpdate;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: colors.surface,
      child: SizedBox(
        width: 290,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : Icons.system_update_rounded,
                    color: failed ? colors.error : colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      failed ? 'Update failed' : 'Update available',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Dismiss',
                  ),
                ],
              ),
              Text(
                'SmartStore ${update.version}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
              if (failed) ...[
                const SizedBox(height: 8),
                const Text(
                  'The update could not be installed. Try again later.',
                ),
              ] else if (update.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  update.releaseNotes.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: failed ? onRetry : onUpdate,
                  icon: Icon(
                    failed ? Icons.refresh_rounded : Icons.download_rounded,
                    size: 17,
                  ),
                  label: Text(failed ? 'Try again' : 'Update'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateOverlay extends StatelessWidget {
  const _UpdateOverlay({required this.status, required this.progress});

  final UpdateStatus status;
  final double? progress;

  String get message => switch (status) {
    UpdateStatus.downloading => 'Downloading update...',
    UpdateStatus.verifying => 'Verifying update...',
    UpdateStatus.installing => 'Installing update...',
    UpdateStatus.restarting => 'Restarting SmartStore...',
    _ => 'Updating SmartStore...',
  };

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    const Text(
                      'Updating SmartStore',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message),
                    if (progress != null) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 6),
                      Text('${(progress! * 100).round()}%'),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

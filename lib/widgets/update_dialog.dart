import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/update_service.dart';

Future<void> showUpdateDialog({
  required BuildContext context,
  required UpdateService service,
  required String currentVersion,
}) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) =>
        UpdateDialog(service: service, currentVersion: currentVersion),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.service,
    required this.currentVersion,
  });

  final UpdateService service;
  final String currentVersion;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(service.checkForUpdate(force: true));
      }
    });
  }

  UpdateService get service => widget.service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final status = service.status;
        final update = service.update;
        final busy = service.isUpdating;
        final canCancel = status == UpdateStatus.downloading;
        final canClose = !busy || canCancel;
        final notes = update?.releaseNotes.isNotEmpty == true
            ? update!.releaseNotes
            : <String>['update.fallback_notes'.tr()];

        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  status == UpdateStatus.failed ||
                          status == UpdateStatus.checkFailed
                      ? Icons.error_outline_rounded
                      : Icons.system_update_alt_rounded,
                  color:
                      status == UpdateStatus.failed ||
                          status == UpdateStatus.checkFailed
                      ? colors.error
                      : colors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'update.title'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status == UpdateStatus.checking) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 16),
                      Center(child: Text('update.checking'.tr())),
                    ] else if (status == UpdateStatus.checkFailed) ...[
                      Text('update.check_failed'.tr()),
                    ] else if (update == null) ...[
                      Text(
                        'update.current_title'.tr(),
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('update.no_update'.tr()),
                    ] else ...[
                      Text(
                        update.title,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'update.version_comparison'.tr(
                          args: [widget.currentVersion, update.version],
                        ),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'update.whats_new'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(note)),
                            ],
                          ),
                        ),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 16),
                      Text(_statusLabel(status)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: status == UpdateStatus.downloading
                            ? service.progress?.clamp(0.0, 1.0)
                            : null,
                      ),
                      if (service.progress != null && canCancel) ...[
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${(service.progress! * 100).round()}%',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (status == UpdateStatus.failed &&
                        update != null &&
                        service.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        'update.download_error'.tr(),
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(
              onPressed: canClose
                  ? () {
                      if (canCancel) service.cancelDownload();
                      Navigator.of(context).pop();
                    }
                  : null,
              child: Text(
                canCancel ? 'update.cancel_download'.tr() : 'update.later'.tr(),
              ),
            ),
            if (status == UpdateStatus.checkFailed)
              FilledButton.icon(
                onPressed: () => service.checkForUpdate(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('update.retry_check'.tr()),
              )
            else if (update != null)
              FilledButton.icon(
                onPressed: busy ? null : service.install,
                icon: Icon(
                  status == UpdateStatus.failed
                      ? Icons.refresh_rounded
                      : Icons.download_rounded,
                  size: 18,
                ),
                label: Text(
                  status == UpdateStatus.failed
                      ? 'update.retry'.tr()
                      : 'update.now'.tr(),
                ),
              ),
          ],
        );
      },
    );
  }

  String _statusLabel(UpdateStatus status) => switch (status) {
    UpdateStatus.downloading => 'update.downloading'.tr(),
    UpdateStatus.verifying => 'update.verifying'.tr(),
    UpdateStatus.installing => 'update.installing'.tr(),
    UpdateStatus.restarting => 'update.restarting'.tr(),
    UpdateStatus.checkFailed => 'update.check_failed'.tr(),
    _ => 'update.working'.tr(),
  };
}

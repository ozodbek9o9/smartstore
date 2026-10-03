import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/connected_devices_service.dart';

class ConnectedDevicesCard extends StatefulWidget {
  const ConnectedDevicesCard({super.key, required this.accountReference});

  final DocumentReference<Map<String, dynamic>> accountReference;

  @override
  State<ConnectedDevicesCard> createState() => _ConnectedDevicesCardState();
}

class _ConnectedDevicesCardState extends State<ConnectedDevicesCard> {
  final _service = ConnectedDevicesService();
  late final Future<String> _deviceId = _service.getDeviceId();
  bool _savingLimit = false;
  String? _removingDeviceId;

  Future<void> _setLimit(int limit) async {
    setState(() => _savingLimit = true);
    try {
      await _service.setLimit(widget.accountReference, limit);
      _showMessage('devices.saved'.tr());
    } catch (error) {
      _showMessage('devices.load_error'.tr(), isError: true);
      debugPrint('Unable to save connected-device limit: $error');
    } finally {
      if (mounted) setState(() => _savingLimit = false);
    }
  }

  Future<void> _removeDevice(String deviceId, String deviceName) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('devices.remove_title'.tr()),
        content: Text('devices.remove_confirmation'.tr(args: [deviceName])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('devices.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('devices.remove'.tr()),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) return;

    setState(() => _removingDeviceId = deviceId);
    try {
      await _service.removeDevice(widget.accountReference, deviceId);
      _showMessage('devices.removed'.tr());
    } catch (error) {
      _showMessage('devices.load_error'.tr(), isError: true);
      debugPrint('Unable to remove connected device: $error');
    } finally {
      if (mounted) setState(() => _removingDeviceId = null);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: isDark ? 0 : 4,
      shadowColor: Colors.black.withOpacity(0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.accountReference.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _errorState(colors);
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final account = snapshot.data!.data() ?? const <String, dynamic>{};
            final rawDevices = account['connectedDevices'];
            final devices = rawDevices is Map
                ? rawDevices.map(
                    (key, value) => MapEntry(
                      key.toString(),
                      value is Map
                          ? Map<String, dynamic>.from(value)
                          : <String, dynamic>{},
                    ),
                  )
                : <String, Map<String, dynamic>>{};
            final rawLimit = account['deviceLimit'];
            final limit = rawLimit is num
                ? rawLimit.toInt().clamp(
                    ConnectedDevicesService.minimumLimit,
                    ConnectedDevicesService.maximumLimit,
                  )
                : ConnectedDevicesService.defaultLimit;
            final entries = devices.entries.toList()
              ..sort(
                (left, right) =>
                    _lastSeen(right.value).compareTo(_lastSeen(left.value)),
              );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.devices_rounded,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'devices.title'.tr(),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'devices.description'.tr(),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final limitControl = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text('devices.limit'.tr())),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 108,
                          child: DropdownButtonFormField<int>(
                            initialValue: limit,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: [
                              for (var count = 1; count <= 10; count++)
                                DropdownMenuItem(
                                  value: count,
                                  child: Text('$count'),
                                ),
                            ],
                            onChanged: _savingLimit
                                ? null
                                : (value) {
                                    if (value != null && value != limit) {
                                      _setLimit(value);
                                    }
                                  },
                          ),
                        ),
                      ],
                    );
                    final usage = Text(
                      'devices.count'.tr(
                        args: [devices.length.toString(), limit.toString()],
                      ),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          limitControl,
                          const SizedBox(height: 10),
                          usage,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: limitControl),
                        usage,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: borderColor),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'devices.empty'.tr(),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  FutureBuilder<String>(
                    future: _deviceId,
                    builder: (context, deviceIdSnapshot) => Column(
                      children: [
                        for (
                          var index = 0;
                          index < entries.length;
                          index++
                        ) ...[
                          if (index > 0) Divider(height: 1, color: borderColor),
                          _deviceRow(
                            entries[index].key,
                            entries[index].value,
                            deviceIdSnapshot.data,
                            colors,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _deviceRow(
    String deviceId,
    Map<String, dynamic> device,
    String? currentDeviceId,
    ColorScheme colors,
  ) {
    final name = device['name']?.toString().trim().isNotEmpty == true
        ? device['name'].toString()
        : 'devices.unknown_device'.tr();
    final isCurrent = deviceId == currentDeviceId;
    final lastSeen = _lastSeen(device);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.computer_rounded,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'devices.current'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF047857),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'devices.last_seen'.tr(
                    args: [
                      DateFormat.yMMMd().add_jm().format(lastSeen.toLocal()),
                    ],
                  ),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              tooltip: 'devices.remove'.tr(),
              onPressed: _removingDeviceId == deviceId
                  ? null
                  : () => _removeDevice(deviceId, name),
              icon: _removingDeviceId == deviceId
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
    );
  }

  Widget _errorState(ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: colors.error),
        const SizedBox(width: 12),
        Expanded(child: Text('devices.load_error'.tr())),
      ],
    ),
  );

  DateTime _lastSeen(Map<String, dynamic> device) {
    final value = device['lastSeenAt'] ?? device['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1970);
    return DateTime(1970);
  }
}

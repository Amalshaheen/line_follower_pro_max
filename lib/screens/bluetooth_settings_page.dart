import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show ScanResult, BluetoothAdapterState, FlutterBluePlus;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
    show BluetoothDevice;

import '../constants/app_constants.dart';
import '../services/robot_service.dart';

/// Unified connection settings screen.
///
/// Shows a mode toggle (Classic BT / BLE) and the appropriate device list for
/// the selected mode.  Calls back to the dashboard for all state changes.
class BluetoothSettingsPage extends StatefulWidget {
  // ── Classic BT ─────────────────────────────────────────────────────────────
  final List<BluetoothDevice> bondedDevices;
  final BluetoothDevice? selectedClassicDevice;

  // ── BLE ─────────────────────────────────────────────────────────────────────
  final List<ScanResult> scanResults;
  final ScanResult? selectedScanResult;
  final bool isScanning;
  final Stream<BluetoothAdapterState>? bleAdapterStateStream;

  // ── Shared ──────────────────────────────────────────────────────────────────
  final ConnectionMode connectionMode;
  final bool isConnected;
  final bool isConnecting;
  final String btStatus;
  final String deviceName; // configurable device name

  // ── Callbacks ───────────────────────────────────────────────────────────────
  final ValueChanged<ConnectionMode> onModeChanged;
  final ValueChanged<String> onDeviceNameChanged;
  final ValueChanged<BluetoothDevice> onClassicDeviceSelected;
  final ValueChanged<ScanResult> onBleDeviceSelected;
  final Future<bool> Function() onConnect;
  final VoidCallback onDisconnect;
  final Future<List<BluetoothDevice>> Function() onRefreshClassic;
  final VoidCallback onStartBleScan;

  const BluetoothSettingsPage({
    super.key,
    required this.bondedDevices,
    required this.selectedClassicDevice,
    required this.scanResults,
    required this.selectedScanResult,
    required this.isScanning,
    required this.bleAdapterStateStream,
    required this.connectionMode,
    required this.isConnected,
    required this.isConnecting,
    required this.btStatus,
    required this.deviceName,
    required this.onModeChanged,
    required this.onDeviceNameChanged,
    required this.onClassicDeviceSelected,
    required this.onBleDeviceSelected,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefreshClassic,
    required this.onStartBleScan,
  });

  @override
  State<BluetoothSettingsPage> createState() => _BluetoothSettingsPageState();
}

class _BluetoothSettingsPageState extends State<BluetoothSettingsPage> {
  late final TextEditingController _deviceNameController;
  late bool _isConnected;
  late bool _isConnecting;
  late List<BluetoothDevice> _bondedDevices;
  late String _btStatus;
  bool _isRefreshingClassic = false;

  @override
  void initState() {
    super.initState();
    _deviceNameController = TextEditingController(text: widget.deviceName);
    _isConnected = widget.isConnected;
    _isConnecting = widget.isConnecting;
    _bondedDevices = widget.bondedDevices;
    _btStatus = widget.btStatus;
  }

  @override
  void didUpdateWidget(covariant BluetoothSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceName != widget.deviceName) {
      _deviceNameController.text = widget.deviceName;
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  bool get _isBle => widget.connectionMode == ConnectionMode.ble;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.bluetoothSettingsTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildModeToggleCard(context),
            const SizedBox(height: 12),
            _buildDeviceNameCard(context),
            const SizedBox(height: 12),
            _buildConnectionStatusCard(context),
            const SizedBox(height: 12),
            _isBle
                ? _buildBleDeviceListCard(context)
                : _buildClassicDeviceCard(context),
            if (widget.isConnecting) ...[
              const SizedBox(height: 12),
              _buildConnectingIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode toggle
  // ---------------------------------------------------------------------------

  Widget _buildModeToggleCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Type',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Classic BT requires a paired/bonded device.\nBLE scans nearby and connects without pairing.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<ConnectionMode>(
              segments: const [
                ButtonSegment(
                  value: ConnectionMode.classic,
                  label: Text('Classic BT'),
                  icon: Icon(Icons.bluetooth),
                ),
                ButtonSegment(
                  value: ConnectionMode.ble,
                  label: Text('BLE'),
                  icon: Icon(Icons.bluetooth_searching),
                ),
              ],
              selected: {widget.connectionMode},
              onSelectionChanged: _isConnected
                  ? null
                  : (Set<ConnectionMode> s) => widget.onModeChanged(s.first),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Configurable device name
  // ---------------------------------------------------------------------------

  Widget _buildDeviceNameCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Robot Device Name',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _isBle
                  ? 'Used to filter BLE scan results.'
                  : 'For reference — select device from the list below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deviceNameController,
                    enabled: !_isConnected,
                    decoration: const InputDecoration(
                      labelText: 'Device name',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (v) => widget.onDeviceNameChanged(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _isConnected
                      ? null
                      : () => widget.onDeviceNameChanged(
                            _deviceNameController.text.trim(),
                          ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Connection status
  // ---------------------------------------------------------------------------

  Widget _buildConnectionStatusCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _isConnected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_disabled_rounded,
                  color: _isConnected
                      ? Colors.green
                      : Theme.of(context).disabledColor,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _btStatus,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                if (_isConnecting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_isConnected)
                  OutlinedButton.icon(
                    onPressed: () {
                      widget.onDisconnect();
                      setState(() {
                        _isConnected = false;
                        _btStatus = 'Disconnected';
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Disconnect'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _handleConnect,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Connect'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);
    final success = await widget.onConnect();
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _isConnected = success;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Classic BT device list
  // ---------------------------------------------------------------------------

  Widget _buildClassicDeviceCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paired Devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.selectedClassicDevice?.address,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Select Device',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: _bondedDevices
                  .map(
                    (device) => DropdownMenuItem<String>(
                      value: device.address,
                      child: Text(
                        device.name ?? device.address,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isConnected
                  ? null
                  : (address) {
                      if (address == null) return;
                      final device = _bondedDevices.firstWhere(
                        (d) => d.address == address,
                      );
                      widget.onClassicDeviceSelected(device);
                    },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isConnected || _isRefreshingClassic
                  ? null
                  : () async {
                      setState(() => _isRefreshingClassic = true);
                      final devices = await widget.onRefreshClassic();
                      if (mounted) {
                        setState(() {
                          _bondedDevices = devices;
                          _isRefreshingClassic = false;
                        });
                      }
                    },
              icon: _isRefreshingClassic
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text(AppConstants.refreshButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BLE scan results list
  // ---------------------------------------------------------------------------

  Widget _buildBleDeviceListCard(BuildContext context) {
    return StreamBuilder<List<ScanResult>>(
      stream: FlutterBluePlus.scanResults,
      initialData: const [],
      builder: (context, snapshot) {
        final results = snapshot.data ?? [];
        final deviceName = widget.deviceName.trim().toLowerCase();

        final sorted = [...results]..sort((a, b) {
            final aName = a.device.platformName.toLowerCase();
            final bName = b.device.platformName.toLowerCase();
            final aMatch =
                deviceName.isEmpty || aName.contains(deviceName) ? 0 : 1;
            final bMatch =
                deviceName.isEmpty || bName.contains(deviceName) ? 0 : 1;
            if (aMatch != bMatch) return aMatch - bMatch;
            return b.rssi.compareTo(a.rssi);
          });

        return StreamBuilder<bool>(
          stream: FlutterBluePlus.isScanning,
          initialData: false,
          builder: (context, scanSnapshot) {
            final isScanning = scanSnapshot.data ?? false;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'BLE Devices',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        if (isScanning)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _isConnected ? null : widget.onStartBleScan,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text(AppConstants.scanButtonLabel),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sorted.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            isScanning
                                ? 'Scanning for BLE devices…'
                                : 'No devices found. Press Scan to search.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sorted.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final r = sorted[index];
                          final name = r.device.platformName.isEmpty
                              ? r.device.remoteId.str
                              : r.device.platformName;
                          final isSelected =
                              widget.selectedScanResult?.device.remoteId ==
                                  r.device.remoteId;
                          final isMatch = deviceName.isEmpty ||
                              name.toLowerCase().contains(deviceName);

                          return ListTile(
                            leading: Icon(
                              Icons.bluetooth_rounded,
                              color: isMatch ? Theme.of(context).colorScheme.primary : null,
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontWeight: isMatch ? FontWeight.w600 : null,
                              ),
                            ),
                            subtitle: Text('RSSI: ${r.rssi} dBm'),
                            trailing: _isConnected && isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null,
                            selected: isSelected,
                            onTap: _isConnected
                                ? null
                                : () => widget.onBleDeviceSelected(r),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Connecting indicator
  // ---------------------------------------------------------------------------

  Widget _buildConnectingIndicator() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Connecting…'),
          ],
        ),
      ),
    );
  }
}

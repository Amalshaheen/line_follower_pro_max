import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../constants/app_constants.dart';

/// Screen for managing Bluetooth device connections and settings.
class BluetoothSettingsPage extends StatelessWidget {
  final List<BluetoothDevice> bondedDevices;
  final BluetoothDevice? selectedDevice;
  final bool isConnected;
  final bool isConnecting;
  final String btStatus;
  final Function(BluetoothDevice) onDeviceSelected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRefresh;

  const BluetoothSettingsPage({
    super.key,
    required this.bondedDevices,
    required this.selectedDevice,
    required this.isConnected,
    required this.isConnecting,
    required this.btStatus,
    required this.onDeviceSelected,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.bluetoothSettingsTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConnectionStatusCard(context),
              const SizedBox(height: 16),
              _buildDeviceSelectionCard(context),
              if (isConnecting) ...[
                const SizedBox(height: 16),
                _buildConnectingIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatusCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Connection Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (isConnected) _buildConnectedBadge(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              btStatus,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (selectedDevice != null && !isConnected) ...[
              const SizedBox(height: 8),
              Text(
                'Device: ${selectedDevice!.name ?? selectedDevice!.address}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Connected',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelectionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Devices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedDevice?.address,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Select Device',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: bondedDevices
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
              onChanged: isConnected
                  ? null
                  : (address) {
                      if (address == null) return;
                      final device = bondedDevices.firstWhere(
                        (device) => device.address == address,
                      );
                      onDeviceSelected(device);
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isConnected ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(AppConstants.refreshButtonLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: isConnected ? onDisconnect : onConnect,
                    icon: Icon(
                      isConnected
                          ? Icons.bluetooth_disabled
                          : Icons.bluetooth_connected,
                    ),
                    label: Text(
                      isConnected
                          ? AppConstants.disconnectButtonLabel
                          : AppConstants.connectButtonLabel,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
            Text('Connecting...'),
          ],
        ),
      ),
    );
  }
}

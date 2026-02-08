import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../live/ble_controller.dart';
import '../../live/ble_codec.dart';
import '../../live/charger_telemetry.dart';
import '../../live/oem_command_mapper.dart';

class HubScreen extends StatefulWidget {
  const HubScreen({
    super.key,
    required this.onOpenReplay,
    required this.onOpenLive,
    required this.onOpenTelemetry,
  });

  final VoidCallback onOpenReplay;
  final VoidCallback onOpenLive;
  final VoidCallback onOpenTelemetry;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen>
    with SingleTickerProviderStateMixin {
  static const _oemBlue = Color(0xFF1E88E5);
  static const _lineColor = Color(0xFFDADADA);
  static const _valueBlue = Color(0xFF2437C8);
  static const _maxSaveTrack = 40;

  late final TabController _tabController;

  final TextEditingController _outputVoltageController = TextEditingController(
    text: '149.0',
  );
  final TextEditingController _outputCurrentController = TextEditingController(
    text: '0.5',
  );

  final TextEditingController _powerOffCurrentController =
      TextEditingController(text: '0.3');
  final TextEditingController _secondStageVoltageController =
      TextEditingController(text: '150.0');
  final TextEditingController _secondStageCurrentController =
      TextEditingController(text: '0.8');
  final TextEditingController _softStartController = TextEditingController(
    text: '8',
  );
  final TextEditingController _powerLimitController = TextEditingController(
    text: '1500',
  );
  final TextEditingController _bluetoothNameController = TextEditingController(
    text: 'ChargeFast',
  );
  final TextEditingController _originalPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _powerOnOutput = true;
  bool _selfStop = false;
  bool _twoStage = true;
  bool _manualControl = true;
  bool? _powerOnOutputLocal;
  bool? _selfStopLocal;
  bool? _twoStageLocal;
  bool? _manualControlLocal;
  bool? _outputEnabledLocal;
  final List<_SaveTrackEntry> _saveTrack = [];

  String _multiMotorMode = 'Intelligent Control';
  String _displayLanguage = 'English';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outputVoltageController.dispose();
    _outputCurrentController.dispose();
    _powerOffCurrentController.dispose();
    _secondStageVoltageController.dispose();
    _secondStageCurrentController.dispose();
    _softStartController.dispose();
    _powerLimitController.dispose();
    _bluetoothNameController.dispose();
    _originalPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BleController>();
    final telemetry = ChargerTelemetryState.fromLogs(controller.rxLogs);
    _syncToggleStateFromTelemetry(telemetry);
    return Scaffold(
      backgroundColor: const Color(0xFFEFEFEF),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(controller, telemetry),
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: _oemBlue,
                unselectedLabelColor: Colors.black87,
                indicatorColor: _oemBlue,
                tabs: const [
                  Tab(text: 'Output'),
                  Tab(text: 'Settings'),
                  Tab(text: 'Safety'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOutputTab(telemetry),
                  _buildSettingsTab(telemetry),
                  _buildSafetyTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BleController controller,
    ChargerTelemetryState telemetry,
  ) {
    return Container(
      color: _oemBlue,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _tabController.animateTo(0),
            icon: const Icon(Icons.chevron_left),
            color: Colors.white,
          ),
          const Text(
            'ChargeFast',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          _statusChip(
            controller.isConnected ? 'Connected' : 'Disconnected',
            controller.isConnected,
          ),
          const SizedBox(width: 6),
          _statusChip('RX ${controller.rxLogs.length}', true),
          if (telemetry.lastRxAt != null) ...[
            const SizedBox(width: 6),
            _statusChip('Live', true),
          ],
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0C6ED2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onOpenReplay,
                  icon: const Icon(Icons.star_border),
                  color: Colors.white,
                  tooltip: 'Replay',
                ),
                IconButton(
                  onPressed: widget.onOpenLive,
                  icon: const Icon(Icons.more_horiz),
                  color: Colors.white,
                  tooltip: 'Live',
                ),
                IconButton(
                  onPressed: widget.onOpenTelemetry,
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  tooltip: 'Telemetry',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, bool positive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: positive ? const Color(0x3300C853) : const Color(0x55B0BEC5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildOutputTab(ChargerTelemetryState telemetry) {
    return _tabScaffold(
      ListView(
        padding: EdgeInsets.zero,
        children: [
          _plainInfoRow(
            'Firmware Version: ${telemetry.firmwareVersion ?? '--'}',
          ),
          _sectionHeader('Display information'),
          _metricPairRow(
            leftLabel: 'Input voltage',
            leftValue: _fmtNum(telemetry.inputVoltage, unit: 'V'),
            rightLabel: 'Input current',
            rightValue: _fmtNum(telemetry.inputCurrent, unit: 'A'),
          ),
          _metricPairRow(
            leftLabel: 'Output voltage',
            leftValue: _fmtNum(telemetry.outputVoltage, unit: 'V'),
            rightLabel: 'Output current',
            rightValue: _fmtNum(telemetry.outputCurrent, unit: 'A'),
          ),
          _metricPairRow(
            leftLabel: 'Input frequency',
            leftValue: _fmtNum(telemetry.inputFrequencyHz, unit: 'Hz'),
            rightLabel: 'Efficiency',
            rightValue: _fmtNum(telemetry.efficiencyPercent, unit: '%'),
          ),
          _metricPairRow(
            leftLabel: 'Input power',
            leftValue: _fmtNum(telemetry.inputPowerW, unit: 'W'),
            rightLabel: 'Output power',
            rightValue: _fmtNum(telemetry.outputPowerW, unit: 'W'),
          ),
          _metricPairRow(
            leftLabel: 'Throttling Point',
            leftValue: _fmtNum(telemetry.throttlingPercent, unit: '%'),
            rightLabel: 'Temperature',
            rightValue: _fmtNum(telemetry.temperatureC, unit: '°C'),
          ),
          _metricPairRow(
            leftLabel: 'Temperature 2',
            leftValue: _fmtNum(telemetry.temperature2C, unit: '°C'),
            rightLabel: '',
            rightValue: '',
          ),
          _sectionHeader('Settings'),
          _statsRow(),
          _numericSettingRow(
            label: 'Current Voltage',
            currentText:
                '(${_fmtNum(telemetry.outputSetVoltage, unit: 'V', fallback: '--')})',
            controller: _outputVoltageController,
            unit: 'V',
            saveKey: 'output_current_voltage',
          ),
          _numericSettingRow(
            label: 'Current',
            currentText:
                '(${_fmtNum(telemetry.outputSetCurrent, unit: 'A', fallback: '--')})',
            controller: _outputCurrentController,
            unit: 'A',
            saveKey: 'output_current_limit',
          ),
          _outputButtonRow(telemetry),
          _saveTrackSection(),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ChargerTelemetryState telemetry) {
    final powerOnOutputReported = telemetry.powerOnOutput;
    final powerOnOutputValue =
        _powerOnOutputLocal ?? powerOnOutputReported ?? _powerOnOutput;
    final selfStopValue = _selfStopLocal ?? _selfStop;
    final twoStageValue = _twoStageLocal ?? _twoStage;
    final manualControlValue = _manualControlLocal ?? _manualControl;

    final powerOnOutputCurrent = _labelBoolReported(powerOnOutputReported);
    final selfStopCurrent = _labelBool(telemetry.selfStop, fallback: _selfStop);
    final twoStageCurrent = _labelBool(
      telemetry.twoStageEnabled,
      fallback: _twoStage,
    );
    final manualControlCurrent = _labelBool(
      telemetry.manualControl,
      fallback: _manualControl,
    );
    final multiMotorCurrent = telemetry.equalDistributionMode == null
        ? _multiMotorMode
        : (telemetry.equalDistributionMode!
              ? 'Equal Distribution'
              : 'Intelligent Control');
    final displayLanguageCurrent =
        telemetry.displayLanguage ?? _displayLanguage;

    return _tabScaffold(
      ListView(
        padding: EdgeInsets.zero,
        children: [
          _toggleSettingRow(
            label: 'Power-on output',
            currentText: powerOnOutputCurrent,
            value: powerOnOutputValue,
            onChanged: (v) => setState(() {
              _powerOnOutputLocal = v;
            }),
            saveKey: 'power_on_output',
          ),
          _toggleSettingRow(
            label: 'Full of self-stop',
            currentText: selfStopCurrent,
            value: selfStopValue,
            onChanged: (v) => setState(() {
              _selfStopLocal = v;
            }),
            saveKey: 'self_stop',
          ),
          _numericSettingRow(
            label: 'Power-off current',
            currentText:
                '(${_fmtNum(telemetry.powerOffCurrent, unit: 'A', fallback: '--')})',
            controller: _powerOffCurrentController,
            unit: 'A',
            saveKey: 'power_off_current',
          ),
          _toggleSettingRow(
            label: 'Two-stage switch',
            currentText: twoStageCurrent,
            value: twoStageValue,
            onChanged: (v) => setState(() {
              _twoStageLocal = v;
            }),
            saveKey: 'two_stage_switch',
          ),
          _numericSettingRow(
            label: 'Second-stage voltage',
            currentText:
                '(${_fmtNum(telemetry.stage2Voltage, unit: 'V', fallback: '--')})',
            controller: _secondStageVoltageController,
            unit: 'V',
            saveKey: 'second_stage_voltage',
          ),
          _numericSettingRow(
            label: 'Second-stage current',
            currentText:
                '(${_fmtNum(telemetry.stage2Current, unit: 'A', fallback: '--')})',
            controller: _secondStageCurrentController,
            unit: 'A',
            saveKey: 'second_stage_current',
          ),
          _selectSettingRow(
            label: 'Multi-motor current',
            currentText: '($multiMotorCurrent)',
            value: _multiMotorMode,
            options: const ['Intelligent Control', 'Equal Distribution'],
            onChanged: (v) => setState(() => _multiMotorMode = v),
            saveKey: 'multi_motor_current_mode',
          ),
          _toggleSettingRow(
            label: 'Manual control',
            currentText: manualControlCurrent,
            value: manualControlValue,
            onChanged: (v) => setState(() {
              _manualControlLocal = v;
            }),
            saveKey: 'manual_control',
          ),
          _numericSettingRow(
            label: 'Soft start time',
            currentText:
                '(${_fmtInt(telemetry.softStartSeconds, unit: 'S', fallback: '--')})',
            controller: _softStartController,
            unit: 'S',
            saveKey: 'soft_start_time',
          ),
          _numericSettingRow(
            label: 'Power Limit',
            currentText: '(${_powerLimitController.text}W)',
            controller: _powerLimitController,
            unit: 'W',
            saveKey: 'power_limit',
          ),
          _selectSettingRow(
            label: 'Display language',
            currentText: '($displayLanguageCurrent)',
            value: _displayLanguage,
            options: const ['English', 'Chinese'],
            onChanged: (v) => setState(() => _displayLanguage = v),
            saveKey: 'display_language',
          ),
          _saveTrackSection(),
        ],
      ),
    );
  }

  Widget _buildSafetyTab() {
    return _tabScaffold(
      ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _lineColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  flex: 4,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      'Bluetooth\nName',
                      style: TextStyle(fontSize: 19),
                    ),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: TextField(
                    controller: _bluetoothNameController,
                    maxLength: 16,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'ChargeFast',
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: _saveButton(
                    onPressed: () => _saved('safety_bluetooth_name'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: const Text(
              'Change Password',
              style: TextStyle(fontSize: 23),
            ),
          ),
          _safetyPasswordField(
            label: 'Original password',
            controller: _originalPasswordController,
          ),
          _safetyPasswordField(
            label: 'New password',
            controller: _newPasswordController,
          ),
          _safetyPasswordField(
            label: 'Confirm new password',
            controller: _confirmPasswordController,
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _oemBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: _changePassword,
                child: const Text(
                  'Change Password',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: const Text(
              'Friendly reminder: Be sure to remember your password, once you forget it, it cannot be reset.',
              style: TextStyle(fontSize: 16, color: _valueBlue),
            ),
          ),
          _saveTrackSection(),
        ],
      ),
    );
  }

  Widget _tabScaffold(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: child,
      ),
    );
  }

  Widget _plainInfoRow(String text) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: const TextStyle(fontSize: 22)),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: _lineColor),
          bottom: BorderSide(color: _lineColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(title, style: const TextStyle(fontSize: 19)),
    );
  }

  Widget _metricPairRow({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _metricCell(label: leftLabel, value: leftValue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _metricCell(label: rightLabel, value: rightValue),
          ),
        ],
      ),
    );
  }

  Widget _metricCell({required String label, required String value}) {
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 17))),
        Text(value, style: const TextStyle(fontSize: 21, color: _valueBlue)),
      ],
    );
  }

  Widget _statsRow() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Text('Charging Statistics', style: TextStyle(fontSize: 16)),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              '--',
              style: TextStyle(fontSize: 18, color: _valueBlue),
            ),
          ),
          const Expanded(
            flex: 2,
            child: Text(
              '--',
              style: TextStyle(fontSize: 18, color: _valueBlue),
            ),
          ),
          SizedBox(
            width: 110,
            child: _saveButton(
              text: 'Zeroing',
              onPressed: () => _saved('charging_statistics_zero'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleSettingRow({
    required String label,
    required String currentText,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String saveKey,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _labelBlock(label: label, currentText: currentText),
          ),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _OemToggle(value: value, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 110,
            child: _saveButton(onPressed: () => _saved(saveKey)),
          ),
        ],
      ),
    );
  }

  Widget _numericSettingRow({
    required String label,
    required String currentText,
    required TextEditingController controller,
    required String unit,
    required String saveKey,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _labelBlock(label: label, currentText: currentText),
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _lineColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(unit, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: _saveButton(onPressed: () => _saved(saveKey)),
          ),
        ],
      ),
    );
  }

  Widget _selectSettingRow({
    required String label,
    required String currentText,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    required String saveKey,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _labelBlock(label: label, currentText: currentText),
          ),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: _lineColor),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFFAFAFA),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  items: options
                      .map(
                        (option) => DropdownMenuItem(
                          value: option,
                          child: Text(option),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) onChanged(next);
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: _saveButton(onPressed: () => _saved(saveKey)),
          ),
        ],
      ),
    );
  }

  Widget _outputButtonRow(ChargerTelemetryState telemetry) {
    final enabled = _outputEnabledLocal ?? telemetry.outputEnabled ?? false;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _labelBlock(
              label: 'Current output',
              currentText: enabled ? '(Open)' : '(Close)',
            ),
          ),
          Expanded(
            flex: 5,
            child: SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _oemBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () async {
                  final next = !enabled;
                  setState(() {
                    _outputEnabledLocal = next;
                  });
                  await _saved(next ? 'output_on' : 'output_off');
                },
                child: Text(
                  enabled ? 'Turn off output' : 'Turn on output',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 110),
        ],
      ),
    );
  }

  Widget _safetyPasswordField({
    required String label,
    required TextEditingController controller,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 19)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLength: 16,
            obscureText: true,
            decoration: InputDecoration(
              counterText: '',
              hintText: label,
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _lineColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _lineColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    final original = _originalPasswordController.text.trim();
    final next = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (original.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showMessage('Fill original, new, and confirm password fields.');
      return;
    }
    if (next != confirm) {
      _showMessage('New password and confirm password do not match.');
      return;
    }
    if (next.length < 4) {
      _showMessage('Password must be at least 4 characters.');
      return;
    }
    await _saved('safety_change_password');
  }

  Widget _labelBlock({required String label, required String currentText}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black, fontSize: 19),
          children: [
            TextSpan(text: '$label\n'),
            TextSpan(
              text: currentText,
              style: const TextStyle(color: _valueBlue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton({String text = 'Save', required VoidCallback onPressed}) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _oemBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed,
        child: Text(text, style: const TextStyle(fontSize: 17)),
      ),
    );
  }

  Widget _saveTrackSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _lineColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Save Tracking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _saveTrack.isEmpty
                    ? null
                    : () => setState(() {
                        _saveTrack.clear();
                      }),
                child: const Text('Clear'),
              ),
            ],
          ),
          if (_saveTrack.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'No save attempts yet.',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            ..._saveTrack.take(8).map((entry) {
              final statusColor = switch (entry.status) {
                _SaveTrackStatus.ack => Colors.green.shade700,
                _SaveTrackStatus.sentNoAck => Colors.orange.shade700,
                _SaveTrackStatus.rejected => Colors.red.shade700,
                _SaveTrackStatus.sendFailed => Colors.red.shade700,
                _SaveTrackStatus.unmapped => Colors.black54,
              };
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        _fmtTrackTime(entry.at),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${entry.key}: ${entry.summary}\n${entry.payloadHex}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.status.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _saved(String key) async {
    final controller = context.read<BleController>();
    final mapping = _resolveMapping(key);
    if (mapping == null) {
      _pushSaveTrack(
        key: key,
        payloadHex: '--',
        status: _SaveTrackStatus.unmapped,
        summary: 'Not mapped',
      );
      _showMessage('$key is not mapped yet (TBD).');
      return;
    }

    final cmdId = _extractCmdId(mapping.payloadHex);
    final sentAt = DateTime.now();
    final success = await controller.sendHex(
      mapping.payloadHex,
      preferWithoutResponse: true,
      note: 'hub:${mapping.label}',
    );

    if (!mounted) return;
    if (success) {
      final confidence = mapping.isCandidate ? 'candidate' : 'verified';
      if (cmdId != null) {
        final ack = await controller.waitForCommandAck(
          cmdId: cmdId,
          after: sentAt,
        );
        if (!mounted) return;
        switch (ack) {
          case CommandAckState.acknowledged:
            _pushSaveTrack(
              key: key,
              payloadHex: mapping.payloadHex,
              status: _SaveTrackStatus.ack,
              summary: 'ACK ($confidence)',
            );
            _showMessage('Sent ${mapping.payloadHex} ($confidence, ACK).');
          case CommandAckState.rejected:
            _pushSaveTrack(
              key: key,
              payloadHex: mapping.payloadHex,
              status: _SaveTrackStatus.rejected,
              summary: 'Rejected ACK ($confidence)',
            );
            _showMessage(
              'Sent ${mapping.payloadHex} ($confidence), but device rejected ACK.',
            );
          case CommandAckState.timeout:
            _pushSaveTrack(
              key: key,
              payloadHex: mapping.payloadHex,
              status: _SaveTrackStatus.sentNoAck,
              summary: 'No ACK ($confidence)',
            );
            _showMessage(
              'Sent ${mapping.payloadHex} ($confidence), no ACK seen.',
            );
        }
        return;
      }
      _pushSaveTrack(
        key: key,
        payloadHex: mapping.payloadHex,
        status: _SaveTrackStatus.sentNoAck,
        summary: 'Sent ($confidence)',
      );
      _showMessage('Sent ${mapping.payloadHex} ($confidence).');
      return;
    }
    _pushSaveTrack(
      key: key,
      payloadHex: mapping.payloadHex,
      status: _SaveTrackStatus.sendFailed,
      summary: controller.lastError ?? 'Send failed',
    );
    _showMessage(controller.lastError ?? 'Send failed.');
  }

  void _pushSaveTrack({
    required String key,
    required String payloadHex,
    required _SaveTrackStatus status,
    required String summary,
  }) {
    if (!mounted) return;
    setState(() {
      _saveTrack.insert(
        0,
        _SaveTrackEntry(
          at: DateTime.now(),
          key: key,
          payloadHex: payloadHex,
          status: status,
          summary: summary,
        ),
      );
      if (_saveTrack.length > _maxSaveTrack) {
        _saveTrack.removeRange(_maxSaveTrack, _saveTrack.length);
      }
    });
  }

  CommandMappingResult? _resolveMapping(String key) {
    switch (key) {
      case 'output_on':
        return OemCommandMapper.outputOpen();
      case 'output_off':
        return OemCommandMapper.outputClose();
      case 'power_on_output':
        return OemCommandMapper.powerOnOutput(
          _powerOnOutputLocal ?? _powerOnOutput,
        );
      case 'self_stop':
        return OemCommandMapper.selfStop(_selfStopLocal ?? _selfStop);
      case 'manual_control':
        return OemCommandMapper.manualControl(
          _manualControlLocal ?? _manualControl,
        );
      case 'two_stage_switch':
        return OemCommandMapper.twoStageSwitch(_twoStageLocal ?? _twoStage);
      case 'power_off_current':
        final value = _parseDouble(_powerOffCurrentController.text);
        if (value == null) {
          _showMessage('Invalid power-off current value.');
          return null;
        }
        return OemCommandMapper.powerOffCurrent(value);
      case 'second_stage_voltage':
        final value = _parseDouble(_secondStageVoltageController.text);
        if (value == null) {
          _showMessage('Invalid second-stage voltage value.');
          return null;
        }
        return OemCommandMapper.secondStageVoltage(value);
      case 'second_stage_current':
        final value = _parseDouble(_secondStageCurrentController.text);
        if (value == null) {
          _showMessage('Invalid second-stage current value.');
          return null;
        }
        return OemCommandMapper.secondStageCurrent(value);
      case 'soft_start_time':
        final value = _parseInt(_softStartController.text);
        if (value == null) {
          _showMessage('Invalid soft start value.');
          return null;
        }
        return OemCommandMapper.softStartSeconds(value);
      case 'power_limit':
        final value = _parseDouble(_powerLimitController.text);
        if (value == null) {
          _showMessage('Invalid power limit value.');
          return null;
        }
        final watts = value.round();
        if ((value - watts).abs() > 0.0001) {
          _showMessage('Power limit must be a whole number of watts.');
          return null;
        }
        return OemCommandMapper.powerLimitWatts(watts);
      case 'output_current_voltage':
        final value = _parseDouble(_outputVoltageController.text);
        if (value == null) {
          _showMessage('Invalid current voltage value.');
          return null;
        }
        return OemCommandMapper.outputVoltageSetpoint(value);
      case 'output_current_limit':
        final value = _parseDouble(_outputCurrentController.text);
        if (value == null) {
          _showMessage('Invalid current limit value.');
          return null;
        }
        return OemCommandMapper.outputCurrentSetpoint(value);
      case 'charging_statistics_zero':
        return OemCommandMapper.chargingStatisticsZero();
      case 'multi_motor_current_mode':
        return OemCommandMapper.multiMotorMode(_multiMotorMode);
      case 'display_language':
        return OemCommandMapper.displayLanguage(_displayLanguage);
      case 'safety_bluetooth_name':
        final value = _bluetoothNameController.text.trim();
        if (value.isEmpty) {
          _showMessage('Bluetooth name cannot be empty.');
          return null;
        }
        return OemCommandMapper.renameCharger(value);
      case 'safety_change_password':
        final value = _newPasswordController.text.trim();
        if (value.isEmpty) {
          _showMessage('New password cannot be empty.');
          return null;
        }
        return OemCommandMapper.setBlePassword(value);
    }
    return null;
  }

  double? _parseDouble(String raw) {
    final sanitized = raw.trim();
    if (sanitized.isEmpty) return null;
    return double.tryParse(sanitized);
  }

  int? _parseInt(String raw) {
    final sanitized = raw.trim();
    if (sanitized.isEmpty) return null;
    return int.tryParse(sanitized);
  }

  int? _extractCmdId(String payloadHex) {
    final bytes = hexToBytes(payloadHex);
    if (bytes == null || bytes.length < 2) return null;
    final frameType = bytes.first;
    if (frameType == 0x06 && bytes.length == 7) return bytes[1];
    if (frameType == 0x05 && bytes.length == 6) return bytes[1];
    return null;
  }

  String _fmtNum(
    double? value, {
    required String unit,
    String fallback = '--',
  }) {
    if (value == null) return fallback;
    final abs = value.abs();
    final fractionDigits = abs >= 100 ? 1 : 2;
    return '${value.toStringAsFixed(fractionDigits)}$unit';
  }

  String _fmtInt(int? value, {required String unit, String fallback = '--'}) {
    if (value == null) return fallback;
    return '$value$unit';
  }

  String _labelBool(bool? value, {required bool fallback}) {
    final effective = value ?? fallback;
    return effective ? '(Open)' : '(Close)';
  }

  String _labelBoolReported(bool? value) {
    if (value == null) return '(--)';
    return value ? '(Open)' : '(Close)';
  }

  String _fmtTrackTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _syncToggleStateFromTelemetry(ChargerTelemetryState telemetry) {
    if (telemetry.powerOnOutput != null) {
      final next = telemetry.powerOnOutput!;
      if (_powerOnOutputLocal == null || _powerOnOutputLocal == next) {
        _powerOnOutput = next;
        _powerOnOutputLocal = null;
      }
    }
    if (telemetry.selfStop != null) {
      final next = telemetry.selfStop!;
      if (_selfStopLocal == null || _selfStopLocal == next) {
        _selfStop = next;
        _selfStopLocal = null;
      }
    }
    if (telemetry.twoStageEnabled != null) {
      final next = telemetry.twoStageEnabled!;
      if (_twoStageLocal == null || _twoStageLocal == next) {
        _twoStage = next;
        _twoStageLocal = null;
      }
    }
    if (telemetry.manualControl != null) {
      final next = telemetry.manualControl!;
      if (_manualControlLocal == null || _manualControlLocal == next) {
        _manualControl = next;
        _manualControlLocal = null;
      }
    }
    if (telemetry.outputEnabled != null &&
        _outputEnabledLocal == telemetry.outputEnabled) {
      _outputEnabledLocal = null;
    }
  }
}

class _OemToggle extends StatelessWidget {
  const _OemToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 110,
        height: 42,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFB0B0B0)),
          color: value ? const Color(0xFF1E88E5) : const Color(0xFFE0E0E0),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 52,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

enum _SaveTrackStatus {
  ack('ACK'),
  sentNoAck('NO_ACK'),
  rejected('REJECTED'),
  sendFailed('FAILED'),
  unmapped('UNMAPPED');

  const _SaveTrackStatus(this.label);
  final String label;
}

class _SaveTrackEntry {
  const _SaveTrackEntry({
    required this.at,
    required this.key,
    required this.payloadHex,
    required this.status,
    required this.summary,
  });

  final DateTime at;
  final String key;
  final String payloadHex;
  final _SaveTrackStatus status;
  final String summary;
}

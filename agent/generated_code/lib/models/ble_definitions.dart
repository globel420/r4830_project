// ignore_for_file: public_member_api_docs, sort_constructors_first
class BleDefinitions {
  final Meta meta;
  final Device device;
  final Transport transport;
  final Keepalive keepalive;
  final Telemetry telemetry;
  final Map<String, BleCommand> commands;
  final Map<String, BleMacro> macros;
  final UiDef ui;

  BleDefinitions({
    required this.meta,
    required this.device,
    required this.transport,
    required this.keepalive,
    required this.telemetry,
    required this.commands,
    required this.macros,
    required this.ui,
  });

  factory BleDefinitions.fromYaml(Map<dynamic, dynamic> yaml) {
    return BleDefinitions(
      meta: Meta.fromYaml(yaml['meta']),
      device: Device.fromYaml(yaml['device']),
      transport: Transport.fromYaml(yaml['transport']),
      keepalive: Keepalive.fromYaml(yaml['keepalive']),
      telemetry: Telemetry.fromYaml(yaml['telemetry']),
      commands: (yaml['commands'] as Map).map((key, value) =>
          MapEntry(key as String, BleCommand.fromYaml(value))),
      macros: (yaml['macros'] as Map? ?? {}).map((key, value) =>
          MapEntry(key as String, BleMacro.fromYaml(value))),
      ui: UiDef.fromYaml(yaml['ui']),
    );
  }
}

class Meta {
  final String schemaVersion;
  final String project;
  final String generatedBy;
  final String lastUpdated;

  Meta({
    required this.schemaVersion,
    required this.project,
    required this.generatedBy,
    required this.lastUpdated,
  });

  factory Meta.fromYaml(Map<dynamic, dynamic> yaml) {
    return Meta(
      schemaVersion: yaml['schema_version'],
      project: yaml['project'],
      generatedBy: yaml['generated_by'],
      lastUpdated: yaml['last_updated'],
    );
  }
}

class Device {
  final List<String> nameContains;
  final String preferredName;
  final String manufacturerId;
  final int rssiMin;

  Device({
    required this.nameContains,
    required this.preferredName,
    required this.manufacturerId,
    required this.rssiMin,
  });

  factory Device.fromYaml(Map<dynamic, dynamic> yaml) {
    return Device(
      nameContains: List<String>.from(yaml['name_contains']),
      preferredName: yaml['preferred_name'],
      manufacturerId: yaml['manufacturer_id'],
      rssiMin: yaml['rssi_min'],
    );
  }
}

class Transport {
  final List<String> serviceUuids;
  final BleCharacteristic tx;
  final BleCharacteristic rx;

  Transport({required this.serviceUuids, required this.tx, required this.rx});

  factory Transport.fromYaml(Map<dynamic, dynamic> yaml) {
    return Transport(
      serviceUuids: (yaml['service_uuids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      tx: BleCharacteristic.fromYaml(yaml['characteristics']['tx']),
      rx: BleCharacteristic.fromYaml(yaml['characteristics']['rx']),
    );
  }
}

class BleCharacteristic {
  final String uuid;
  final String? writeType;
  final bool? notify;
  final bool? indicate;

  BleCharacteristic({required this.uuid, this.writeType, this.notify, this.indicate});

  factory BleCharacteristic.fromYaml(Map<dynamic, dynamic> yaml) {
    return BleCharacteristic(
      uuid: yaml['uuid'],
      writeType: yaml['write_type'],
      notify: yaml['notify'],
      indicate: yaml['indicate'],
    );
  }
}

class Keepalive {
  final bool enabled;
  final String payloadHex;
  final int intervalMs;
  final String sendVia;

  Keepalive({
    required this.enabled,
    required this.payloadHex,
    required this.intervalMs,
    required this.sendVia,
  });

  factory Keepalive.fromYaml(Map<dynamic, dynamic> yaml) {
    return Keepalive(
      enabled: yaml['enabled'],
      payloadHex: yaml['payload_hex'],
      intervalMs: yaml['interval_ms'],
      sendVia: yaml['send_via'],
    );
  }
}

class Telemetry {
  final bool enabled;
  final String source;
  final String decode;

  Telemetry({required this.enabled, required this.source, required this.decode});

  factory Telemetry.fromYaml(Map<dynamic, dynamic> yaml) {
    return Telemetry(
      enabled: yaml['enabled'],
      source: yaml['source'],
      decode: yaml['decode'],
    );
  }
}

class BleCommand {
  final String label;
  final String category;
  final String sendVia;
  final String payloadHex;
  final bool expectsResponse;

  BleCommand({
    required this.label,
    required this.category,
    required this.sendVia,
    required this.payloadHex,
    required this.expectsResponse,
  });

  factory BleCommand.fromYaml(Map<dynamic, dynamic> yaml) {
    return BleCommand(
      label: yaml['label'],
      category: yaml['category'],
      sendVia: yaml['send_via'],
      payloadHex: yaml['payload_hex'],
      expectsResponse: yaml['expects_response'],
    );
  }
}

class BleMacro {
  final String label;
  final String category;
  final List<MacroStep> steps;

  BleMacro({required this.label, required this.category, required this.steps});

  factory BleMacro.fromYaml(Map<dynamic, dynamic> yaml) {
    return BleMacro(
      label: yaml['label'],
      category: yaml['category'],
      steps: (yaml['steps'] as List)
          .map((step) => MacroStep.fromYaml(step))
          .toList(),
    );
  }
}

class MacroStep {
  final String command;

  MacroStep({required this.command});

  factory MacroStep.fromYaml(Map<dynamic, dynamic> yaml) {
    return MacroStep(command: yaml['command']);
  }
}

class UiDef {
  final List<UiGroup> groups;

  UiDef({required this.groups});

  factory UiDef.fromYaml(Map<dynamic, dynamic> yaml) {
    return UiDef(
      groups: (yaml['groups'] as List)
          .map((group) => UiGroup.fromYaml(group))
          .toList(),
    );
  }
}

class UiGroup {
  final String key;
  final String label;
  final int order;
  final List<UiItem> items;

  UiGroup({
    required this.key,
    required this.label,
    required this.order,
    required this.items,
  });

  factory UiGroup.fromYaml(Map<dynamic, dynamic> yaml) {
    return UiGroup(
      key: yaml['key'],
      label: yaml['label'],
      order: yaml['order'],
      items: (yaml['items'] as List)
          .map((item) => UiItem.fromYaml(item))
          .toList(),
    );
  }
}

class UiItem {
  final String type;
  final String label;
  final String? onMacro;
  final String? offMacro;
  final String? onCommand;
  final String? offCommand;
  final List<UiSelectorValue>? values;

  UiItem({
    required this.type,
    required this.label,
    this.onMacro,
    this.offMacro,
    this.onCommand,
    this.offCommand,
    this.values,
  });

  factory UiItem.fromYaml(Map<dynamic, dynamic> yaml) {
    return UiItem(
      type: yaml['type'],
      label: yaml['label'],
      onMacro: yaml['on_macro'],
      offMacro: yaml['off_macro'],
      onCommand: yaml['on_command'],
      offCommand: yaml['off_command'],
      values: (yaml['values'] as List?)
          ?.map((value) => UiSelectorValue.fromYaml(value))
          .toList(),
    );
  }
}

class UiSelectorValue {
  final String label;
  final String command;

  UiSelectorValue({required this.label, required this.command});

  factory UiSelectorValue.fromYaml(Map<dynamic, dynamic> yaml) {
    return UiSelectorValue(
      label: yaml['label'],
      command: yaml['command'],
    );
  }
}

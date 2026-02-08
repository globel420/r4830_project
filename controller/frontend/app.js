const UUIDS = {
  ffe1: "0000ffe1-0000-1000-8000-00805f9b34fb",
  ffe2: "0000ffe2-0000-1000-8000-00805f9b34fb",
  ffe3: "0000ffe3-0000-1000-8000-00805f9b34fb",
};

const MAX_LOG_ROWS = 200;
const MAX_SAVE_TRACK = 40;

const dom = {
  statusPill: document.getElementById("status-pill"),
  devicePill: document.getElementById("device-pill"),
  rxUuid: document.getElementById("rx-uuid"),
  txUuid: document.getElementById("tx-uuid"),
  rxCount: document.getElementById("rx-count"),
  txCount: document.getElementById("tx-count"),
  logBody: document.getElementById("log-body"),
  saveTrack: document.getElementById("save-track"),
  connectBtn: document.getElementById("connect-btn"),
  disconnectBtn: document.getElementById("disconnect-btn"),
  discoverBtn: document.getElementById("discover-btn"),
  rawHex: document.getElementById("raw-hex"),
  sendRawBtn: document.getElementById("send-raw-btn"),
  keepaliveEnabled: document.getElementById("keepalive-enabled"),
  keepaliveMs: document.getElementById("keepalive-ms"),
  setVoltage: document.getElementById("set-voltage"),
  setCurrent: document.getElementById("set-current"),
  powerOffCurrent: document.getElementById("power-off-current"),
  stage2Voltage: document.getElementById("stage2-voltage"),
  stage2Current: document.getElementById("stage2-current"),
  softStart: document.getElementById("soft-start"),
  powerLimit: document.getElementById("power-limit"),
  powerOnOutput: document.getElementById("power-on-output"),
  selfStop: document.getElementById("self-stop"),
  twoStage: document.getElementById("two-stage"),
  multiMotor: document.getElementById("multi-motor"),
  displayLanguage: document.getElementById("display-language"),
  chargerName: document.getElementById("charger-name"),
  blePassword: document.getElementById("ble-password"),
  tmInputV: document.getElementById("tm-input-v"),
  tmInputA: document.getElementById("tm-input-a"),
  tmOutputV: document.getElementById("tm-output-v"),
  tmOutputA: document.getElementById("tm-output-a"),
  tmSetV: document.getElementById("tm-set-v"),
  tmSetA: document.getElementById("tm-set-a"),
  tmStage2V: document.getElementById("tm-stage2-v"),
  tmStage2A: document.getElementById("tm-stage2-a"),
  tmPoweroffA: document.getElementById("tm-poweroff-a"),
  tmSoftStart: document.getElementById("tm-soft-start"),
  tmTwoStage: document.getElementById("tm-two-stage"),
  tmManual: document.getElementById("tm-manual"),
  tmPowerOnOutput: document.getElementById("tm-power-on-output"),
  tmSelfStop: document.getElementById("tm-self-stop"),
  tmLanguage: document.getElementById("tm-language"),
  tmLastRx: document.getElementById("tm-last-rx"),
};

const state = {
  device: null,
  server: null,
  rxChar: null,
  txChar: null,
  rxCount: 0,
  txCount: 0,
  logs: [],
  saveTrack: [],
  keepaliveTimer: null,
  pendingAcks: new Map(),
  telemetry: makeEmptyTelemetry(),
  outputEnabledFrom6905: null,
  outputEnabledFrom3006: null,
  outputEnabledFrom06: null,
};

function makeEmptyTelemetry() {
  return {
    firmwareVersion: null,
    outputSetVoltage: null,
    outputSetCurrent: null,
    inputVoltage: null,
    inputCurrent: null,
    outputVoltage: null,
    outputCurrent: null,
    inputFrequencyHz: null,
    temperatureC: null,
    temperature2C: null,
    throttlingPercent: null,
    inputPowerW: null,
    outputPowerW: null,
    efficiencyPercent: null,
    stage2Voltage: null,
    stage2Current: null,
    powerOffCurrent: null,
    softStartSeconds: null,
    outputEnabled: null,
    manualControl: null,
    twoStageEnabled: null,
    powerOnOutput: null,
    selfStop: null,
    equalDistributionMode: null,
    displayLanguage: null,
    lastRxAt: null,
  };
}

function toHexByte(n) {
  return (n & 0xff).toString(16).padStart(2, "0");
}

function bytesToHex(bytes) {
  return Array.from(bytes, (b) => toHexByte(b)).join("");
}

function hexToBytes(input) {
  const normalized = input.replace(/[^0-9a-f]/gi, "").toLowerCase();
  if (!normalized.length || normalized.length % 2 !== 0) {
    return null;
  }
  const out = [];
  for (let i = 0; i < normalized.length; i += 2) {
    const byte = Number.parseInt(normalized.slice(i, i + 2), 16);
    if (Number.isNaN(byte)) {
      return null;
    }
    out.push(byte);
  }
  return Uint8Array.from(out);
}

function buildFrame06FromDataBytes(cmdId, data0, data1, data2, data3) {
  const out = Uint8Array.from([
    0x06,
    cmdId & 0xff,
    data0 & 0xff,
    data1 & 0xff,
    data2 & 0xff,
    data3 & 0xff,
    0,
  ]);
  let checksum = 0;
  for (let i = 1; i <= 5; i += 1) {
    checksum = (checksum + out[i]) & 0xff;
  }
  out[6] = checksum;
  return out;
}

function buildFrame06Int(cmdId, value) {
  const data = value >>> 0;
  return buildFrame06FromDataBytes(
    cmdId,
    data & 0xff,
    (data >>> 8) & 0xff,
    (data >>> 16) & 0xff,
    (data >>> 24) & 0xff,
  );
}

function buildFrame06Float(cmdId, value) {
  const buffer = new ArrayBuffer(4);
  const view = new DataView(buffer);
  view.setFloat32(0, value, true);
  return buildFrame06FromDataBytes(
    cmdId,
    view.getUint8(0),
    view.getUint8(1),
    view.getUint8(2),
    view.getUint8(3),
  );
}

function buildFrame05FromBytes(cmdId, b0, b1, b2) {
  const out = Uint8Array.from([0x05, cmdId & 0xff, b0 & 0xff, b1 & 0xff, b2 & 0xff, 0]);
  let checksum = 0;
  for (let i = 1; i <= 4; i += 1) {
    checksum = (checksum + out[i]) & 0xff;
  }
  out[5] = checksum;
  return out;
}

function languageLabelFromBytes(b0, b1) {
  if (b0 === 0x65 && b1 === 0x6e) {
    return "English";
  }
  if (b0 === 0x7a && b1 === 0x68) {
    return "Chinese (Simplified)";
  }
  if (b0 === 0x7a && b1 === 0x74) {
    return "Chinese (Traditional)";
  }
  if (typeof b0 === "number" && typeof b1 === "number") {
    return `Unknown (${toHexByte(b0)}${toHexByte(b1)})`;
  }
  return null;
}

function asciiOnly(input) {
  return String(input || "")
    .split("")
    .filter((ch) => {
      const code = ch.charCodeAt(0);
      return code >= 0x20 && code <= 0x7e;
    })
    .join("");
}

function buildFrameAscii(cmdId, rawValue, maxLen = 16) {
  const sanitized = asciiOnly(rawValue).trim();
  const clipped = sanitized.length > maxLen ? sanitized.slice(0, maxLen) : sanitized;
  const dataBytes = [...clipped].map((ch) => ch.charCodeAt(0));
  dataBytes.push(0x00);
  const checksum = (cmdId + dataBytes.reduce((sum, b) => sum + b, 0)) & 0xff;
  const len = dataBytes.length + 1;
  return Uint8Array.from([len, cmdId & 0xff, ...dataBytes, checksum]);
}

function decodePayload(bytesInput) {
  const bytes = Array.from(bytesInput, (b) => b & 0xff);
  const decoded = {
    len: bytes.length,
    hex: bytesToHex(bytes),
  };

  if (bytes.length >= 2) {
    decoded.pkt_prefix = bytesToHex(bytes.slice(0, 2));
  }

  for (let i = 0; i < bytes.length; i += 1) {
    decoded[`u8_${String(i).padStart(2, "0")}`] = bytes[i];
  }

  if (bytes.length >= 4) {
    const buffer = new ArrayBuffer(bytes.length);
    const view = new DataView(buffer);
    for (let i = 0; i < bytes.length; i += 1) {
      view.setUint8(i, bytes[i]);
    }
    for (let off = 0; off <= bytes.length - 4; off += 1) {
      const v = view.getFloat32(off, true);
      decoded[`f32le_off_${String(off).padStart(2, "0")}`] = Number.isFinite(v)
        ? v
        : Number.isNaN(v)
          ? "NaN"
          : "Inf";
    }
  }

  if (bytes.length === 7 && bytes[0] === 0x06) {
    const buffer = new ArrayBuffer(4);
    const view = new DataView(buffer);
    for (let i = 0; i < 4; i += 1) {
      view.setUint8(i, bytes[2 + i]);
    }
    const cmdId = bytes[1];
    const dataU = view.getUint32(0, true);
    const dataI = view.getInt32(0, true);
    const dataF = view.getFloat32(0, true);
    let calc = 0;
    for (let i = 1; i <= 5; i += 1) {
      calc = (calc + bytes[i]) & 0xff;
    }
    decoded.frame_type = "0x06";
    decoded.cmd_id = cmdId;
    decoded.data32_le_u = dataU;
    decoded.data32_le_i = dataI;
    decoded.data32_le_f = Number.isFinite(dataF)
      ? dataF
      : Number.isNaN(dataF)
        ? "NaN"
        : "Inf";
    decoded.checksum = bytes[6];
    decoded.checksum_ok = bytes[6] === calc;
    if (dataU === 0 || dataU === 1) {
      decoded.data32_bool_candidate = dataU === 1;
    }
  }

  if (bytes.length === 6 && bytes[0] === 0x05) {
    let calc = 0;
    for (let i = 1; i <= 4; i += 1) {
      calc = (calc + bytes[i]) & 0xff;
    }
    const data24 = bytes[2] | (bytes[3] << 8) | (bytes[4] << 16);
    decoded.frame_type = "0x05";
    decoded.cmd_id = bytes[1];
    decoded.data24_le_u = data24;
    decoded.checksum = bytes[5];
    decoded.checksum_ok = bytes[5] === calc;
  }

  if (bytes.length === 4 && bytes[0] === 0x03) {
    const cmdId = bytes[1];
    const ackStatus = bytes[2];
    const calc = (cmdId + ackStatus) & 0xff;
    decoded.frame_type = "0x03_ack";
    decoded.cmd_id = cmdId;
    decoded.ack_status = ackStatus;
    decoded.ack_ok = ackStatus === 1;
    decoded.checksum = bytes[3];
    decoded.checksum_ok = bytes[3] === calc;
  }

  return decoded;
}

function formatDecodeSummary(decoded) {
  if (decoded.frame_type === "0x03_ack") {
    return `ACK cmd=0x${toHexByte(decoded.cmd_id)} status=${decoded.ack_status} ok=${decoded.ack_ok}`;
  }
  if (decoded.frame_type === "0x06") {
    const fVal =
      typeof decoded.data32_le_f === "number" ? decoded.data32_le_f.toFixed(3) : decoded.data32_le_f;
    return `0x06 cmd=0x${toHexByte(decoded.cmd_id)} u=${decoded.data32_le_u} f=${fVal} csum=${decoded.checksum_ok}`;
  }
  if (decoded.frame_type === "0x05") {
    return `0x05 cmd=0x${toHexByte(decoded.cmd_id)} data24=${decoded.data24_le_u} csum=${decoded.checksum_ok}`;
  }
  if (decoded.pkt_prefix) {
    return `prefix=${decoded.pkt_prefix} len=${decoded.len}`;
  }
  return `len=${decoded.len}`;
}

function setConnectionState(connected) {
  dom.statusPill.textContent = connected ? "Connected" : "Disconnected";
  dom.statusPill.classList.toggle("online", connected);
  dom.statusPill.classList.toggle("offline", !connected);
  dom.disconnectBtn.disabled = !connected;
  dom.discoverBtn.disabled = !connected;
}

function setDeviceName(name) {
  dom.devicePill.textContent = name || "No device";
}

function setMessage(message) {
  dom.devicePill.textContent = message;
}

function renderCounters() {
  dom.rxCount.textContent = String(state.rxCount);
  dom.txCount.textContent = String(state.txCount);
}

function escapeHtml(input) {
  return input
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderLogs() {
  const rows = state.logs.slice(0, MAX_LOG_ROWS);
  dom.logBody.innerHTML = rows
    .map((entry) => {
      const time = entry.timestamp.toLocaleTimeString();
      const summary = formatDecodeSummary(entry.decoded);
      const dirClass = entry.direction === "RX" ? "rx" : "tx";
      return `<tr>
        <td>${escapeHtml(time)}</td>
        <td class="${dirClass}">${escapeHtml(entry.direction)}</td>
        <td>${escapeHtml(entry.hex)}</td>
        <td>${escapeHtml(summary)}</td>
        <td>${escapeHtml(entry.note || "")}</td>
      </tr>`;
    })
    .join("");
}

function addLog(direction, bytes, note = "") {
  const decoded = decodePayload(bytes);
  const entry = {
    timestamp: new Date(),
    direction,
    hex: bytesToHex(bytes),
    decoded,
    note,
  };
  state.logs.unshift(entry);
  if (state.logs.length > 400) {
    state.logs.length = 400;
  }
  if (direction === "RX") {
    state.rxCount += 1;
    state.telemetry.lastRxAt = entry.timestamp;
    handleRxDecoded(decoded, entry.hex);
  } else {
    state.txCount += 1;
  }
  renderCounters();
  renderLogs();
}

function addSaveTrack(key, payloadHex, status, detail = "") {
  state.saveTrack.unshift({
    at: new Date(),
    key,
    payloadHex,
    status,
    detail,
  });
  if (state.saveTrack.length > MAX_SAVE_TRACK) {
    state.saveTrack.length = MAX_SAVE_TRACK;
  }
  renderSaveTrack();
}

function renderSaveTrack() {
  if (!state.saveTrack.length) {
    dom.saveTrack.innerHTML = `<li class="empty">No save attempts yet.</li>`;
    return;
  }
  dom.saveTrack.innerHTML = state.saveTrack
    .slice(0, 12)
    .map((item) => {
      const statusClass = item.status.toLowerCase();
      const detail = item.detail ? ` ${item.detail}` : "";
      return `<li class="${statusClass}">
        <span class="t">${escapeHtml(item.at.toLocaleTimeString())}</span>
        <span class="k">${escapeHtml(item.key)}</span>
        <span class="s">${escapeHtml(item.status)}</span>
        <span class="p">${escapeHtml(item.payloadHex)}</span>
        <span class="d">${escapeHtml(detail)}</span>
      </li>`;
    })
    .join("");
}

function fmt(value, unit = "", digits = 2) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return "-";
  }
  return `${value.toFixed(digits)}${unit}`;
}

function boolLabel(value, yes = "On", no = "Off") {
  if (value == null) {
    return "-";
  }
  return value ? yes : no;
}

function renderTelemetry() {
  const t = state.telemetry;
  dom.tmInputV.textContent = fmt(t.inputVoltage, "V");
  dom.tmInputA.textContent = fmt(t.inputCurrent, "A");
  dom.tmOutputV.textContent = fmt(t.outputVoltage, "V");
  dom.tmOutputA.textContent = fmt(t.outputCurrent, "A");
  dom.tmSetV.textContent = fmt(t.outputSetVoltage, "V");
  dom.tmSetA.textContent = fmt(t.outputSetCurrent, "A");
  dom.tmStage2V.textContent = fmt(t.stage2Voltage, "V");
  dom.tmStage2A.textContent = fmt(t.stage2Current, "A");
  dom.tmPoweroffA.textContent = fmt(t.powerOffCurrent, "A");
  dom.tmSoftStart.textContent =
    typeof t.softStartSeconds === "number" ? `${t.softStartSeconds}s` : "-";
  dom.tmTwoStage.textContent = boolLabel(t.twoStageEnabled);
  dom.tmManual.textContent = boolLabel(t.manualControl);
  dom.tmPowerOnOutput.textContent = boolLabel(t.powerOnOutput, "Open", "Close");
  dom.tmSelfStop.textContent = boolLabel(t.selfStop);
  dom.tmLanguage.textContent = t.displayLanguage || "-";
  dom.tmLastRx.textContent = t.lastRxAt ? t.lastRxAt.toLocaleTimeString() : "-";
}

function asInt(value) {
  if (typeof value === "number") {
    return Number.isFinite(value) ? Math.trunc(value) : null;
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function asFloat(value) {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

function u8At(decoded, index) {
  return asInt(decoded[`u8_${String(index).padStart(2, "0")}`]);
}

function f32At(decoded, offset) {
  return asFloat(decoded[`f32le_off_${String(offset).padStart(2, "0")}`]);
}

function bounded(value, min, max) {
  if (value == null) {
    return null;
  }
  if (value < min || value > max) {
    return null;
  }
  return value;
}

function parseAscii(decoded, start, maxBytes) {
  const chars = [];
  for (let i = 0; i < maxBytes; i += 1) {
    const v = u8At(decoded, start + i);
    if (v == null || v === 0) {
      break;
    }
    if (v < 0x20 || v > 0x7e) {
      break;
    }
    chars.push(v);
  }
  return chars.length ? String.fromCharCode(...chars) : null;
}

function updateOutputEnabledFromFlags() {
  state.telemetry.outputEnabled =
    state.outputEnabledFrom6905 ??
    state.outputEnabledFrom3006 ??
    state.outputEnabledFrom06 ??
    state.telemetry.outputEnabled;
}

function handleRxDecoded(decoded, hex) {
  if (decoded.frame_type === "0x03_ack") {
    settleAck(decoded.cmd_id, decoded.ack_ok, decoded.ack_status, decoded.checksum_ok, hex);
  }

  const t = state.telemetry;
  const prefix = String(decoded.pkt_prefix || "").toLowerCase();
  const frameType = decoded.frame_type;

  if (prefix === "0b01" && !t.firmwareVersion) {
    const fw = parseAscii(decoded, 2, 24);
    if (fw) {
      t.firmwareVersion = fw;
    }
  }

  if (prefix === "3006") {
    t.inputVoltage = bounded(f32At(decoded, 2), 0, 300) ?? t.inputVoltage;
    t.inputCurrent = bounded(f32At(decoded, 6), 0, 200) ?? t.inputCurrent;
    t.inputFrequencyHz = bounded(f32At(decoded, 10), 0, 500) ?? t.inputFrequencyHz;
    t.temperatureC = bounded(f32At(decoded, 14), -40, 200) ?? t.temperatureC;
    t.temperature2C = bounded(f32At(decoded, 18), -40, 200) ?? t.temperature2C;
    t.outputVoltage = bounded(f32At(decoded, 22), 0, 300) ?? t.outputVoltage;
    t.outputCurrent = bounded(f32At(decoded, 26), 0, 200) ?? t.outputCurrent;
    t.inputPowerW = bounded(f32At(decoded, 30), 0, 50000) ?? t.inputPowerW;
    t.efficiencyPercent = bounded(f32At(decoded, 34), 0, 100) ?? t.efficiencyPercent;
    t.throttlingPercent = bounded(f32At(decoded, 34), 0, 100) ?? t.throttlingPercent;
    const outputFlag = u8At(decoded, 38);
    if (outputFlag === 0 || outputFlag === 1) {
      state.outputEnabledFrom3006 = outputFlag === 1;
    }
  }

  if (prefix === "6905") {
    t.outputSetVoltage = bounded(f32At(decoded, 2), 0, 300) ?? t.outputSetVoltage;
    t.outputSetCurrent = bounded(f32At(decoded, 6), 0, 200) ?? t.outputSetCurrent;
    const powerOnRaw = u8At(decoded, 18);
    if (powerOnRaw === 0 || powerOnRaw === 1) {
      t.powerOnOutput = powerOnRaw === 0;
    }
    t.powerOffCurrent = bounded(f32At(decoded, 44), 0, 200) ?? t.powerOffCurrent;
    const outputFlag = u8At(decoded, 77);
    if (outputFlag === 0 || outputFlag === 1) {
      state.outputEnabledFrom6905 = outputFlag === 1;
    }
    t.stage2Voltage = bounded(f32At(decoded, 78), 0, 300) ?? t.stage2Voltage;
    t.stage2Current = bounded(f32At(decoded, 82), 0, 200) ?? t.stage2Current;
    const manualFlag = u8At(decoded, 86);
    if (manualFlag === 0 || manualFlag === 1) {
      t.manualControl = manualFlag === 1;
    }
    const settingsBits = u8At(decoded, 87);
    if (settingsBits != null) {
      t.selfStop = (settingsBits & 0x02) !== 0;
      t.twoStageEnabled = (settingsBits & 0x04) === 0;
    }
    const softStart = u8At(decoded, 88);
    if (softStart != null && softStart >= 0 && softStart <= 120) {
      t.softStartSeconds = softStart;
    }
    if (!t.displayLanguage) {
      const lang0 = u8At(decoded, 93);
      const lang1 = u8At(decoded, 94);
      t.displayLanguage = languageLabelFromBytes(lang0, lang1) || t.displayLanguage;
    }
  }

  if (frameType === "0x05") {
    const cmd = asInt(decoded.cmd_id);
    if (cmd === 0x2a) {
      const b2 = asInt(decoded.u8_02);
      const b3 = asInt(decoded.u8_03);
      t.displayLanguage = languageLabelFromBytes(b2, b3) || t.displayLanguage;
    }
  }

  if (frameType === "0x06") {
    const cmd = asInt(decoded.cmd_id);
    const valueU = asInt(decoded.data32_le_u);
    const valueF = asFloat(decoded.data32_le_f);
    switch (cmd) {
      case 0x07:
        t.outputSetVoltage = valueF;
        if (t.outputVoltage == null) {
          t.outputVoltage = valueF;
        }
        break;
      case 0x08:
        t.outputSetCurrent = valueF;
        if (t.outputCurrent == null) {
          t.outputCurrent = valueF;
        }
        break;
      case 0x0c:
        if (valueU != null) {
          state.outputEnabledFrom06 = valueU === 0;
        }
        break;
      case 0x0b:
        if (valueU != null) {
          t.powerOnOutput = valueU === 0;
        }
        break;
      case 0x14:
        if (valueU != null) {
          t.selfStop = valueU === 1;
        }
        break;
      case 0x15:
        t.powerOffCurrent = valueF;
        break;
      case 0x20:
        if (valueU != null) {
          t.twoStageEnabled = valueU === 1;
        }
        break;
      case 0x21:
        t.stage2Voltage = valueF;
        break;
      case 0x22:
        t.stage2Current = valueF;
        break;
      case 0x23:
        if (valueU != null) {
          t.manualControl = valueU === 1;
        }
        break;
      case 0x26:
        t.softStartSeconds = valueU;
        break;
      case 0x2f:
        if (valueU != null) {
          t.equalDistributionMode = valueU === 1;
        }
        break;
      default:
        break;
    }
  }

  updateOutputEnabledFromFlags();
  if (t.outputVoltage != null && t.outputCurrent != null) {
    t.outputPowerW = t.outputVoltage * t.outputCurrent;
  }
  renderTelemetry();
}

function queueAck(cmdId, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const token = { resolve, timer: null };
    token.timer = window.setTimeout(() => {
      const queue = state.pendingAcks.get(cmdId);
      if (queue) {
        const idx = queue.indexOf(token);
        if (idx >= 0) {
          queue.splice(idx, 1);
        }
        if (!queue.length) {
          state.pendingAcks.delete(cmdId);
        }
      }
      resolve({ state: "timeout" });
    }, timeoutMs);
    const queue = state.pendingAcks.get(cmdId) || [];
    queue.push(token);
    state.pendingAcks.set(cmdId, queue);
  });
}

function settleAck(cmdId, ackOk, ackStatus, checksumOk, hex) {
  const queue = state.pendingAcks.get(cmdId);
  if (!queue || !queue.length) {
    return;
  }
  const token = queue.shift();
  if (!queue.length) {
    state.pendingAcks.delete(cmdId);
  }
  window.clearTimeout(token.timer);
  if (!checksumOk) {
    token.resolve({
      state: "rejected",
      reason: "bad_checksum",
      ackStatus,
      hex,
    });
    return;
  }
  token.resolve({
    state: ackOk ? "acknowledged" : "rejected",
    ackStatus,
    hex,
  });
}

function normalizeUuid(uuid) {
  return String(uuid || "").toLowerCase();
}

function charSupportsNotify(ch) {
  return Boolean(ch.properties.notify || ch.properties.indicate);
}

function charSupportsWrite(ch) {
  return Boolean(ch.properties.writeWithoutResponse || ch.properties.write);
}

function describeChar(ch, serviceUuid) {
  return `${normalizeUuid(ch.uuid)} @ ${normalizeUuid(serviceUuid)}`;
}

async function discoverCharacteristics() {
  if (!state.server) {
    throw new Error("No GATT server");
  }
  const services = await state.server.getPrimaryServices();
  const all = [];
  for (const service of services) {
    const chars = await service.getCharacteristics();
    for (const ch of chars) {
      all.push({ serviceUuid: normalizeUuid(service.uuid), ch });
    }
  }

  const notifyCandidates = all.filter((x) => charSupportsNotify(x.ch));
  const writeCandidates = all.filter((x) => charSupportsWrite(x.ch));

  const rx =
    notifyCandidates.find((x) => normalizeUuid(x.ch.uuid).includes("ffe2")) ||
    notifyCandidates.find((x) => x.serviceUuid.includes("ffe2")) ||
    notifyCandidates[0] ||
    null;

  const tx =
    writeCandidates.find((x) => normalizeUuid(x.ch.uuid).includes("ffe3")) ||
    writeCandidates.find((x) => x.serviceUuid.includes("ffe3")) ||
    writeCandidates[0] ||
    null;

  if (!tx) {
    throw new Error("No writable characteristic found");
  }

  if (state.rxChar && state._rxHandler) {
    state.rxChar.removeEventListener("characteristicvaluechanged", state._rxHandler);
  }

  state.rxChar = rx ? rx.ch : null;
  state.txChar = tx.ch;

  if (state.rxChar && charSupportsNotify(state.rxChar)) {
    state._rxHandler = (event) => {
      const view = event.target.value;
      const bytes = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
      addLog("RX", bytes, "notify");
    };
    await state.rxChar.startNotifications();
    state.rxChar.addEventListener("characteristicvaluechanged", state._rxHandler);
  }

  dom.rxUuid.textContent = state.rxChar ? describeChar(state.rxChar, rx.serviceUuid) : "-";
  dom.txUuid.textContent = describeChar(state.txChar, tx.serviceUuid);
}

function ensureConnected() {
  if (!state.device || !state.device.gatt || !state.device.gatt.connected || !state.txChar) {
    throw new Error("Not connected");
  }
}

async function writeTx(bytes, note = "") {
  ensureConnected();
  const data = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes);
  if (state.txChar.properties.writeWithoutResponse) {
    await state.txChar.writeValueWithoutResponse(data);
  } else {
    await state.txChar.writeValue(data);
  }
  addLog("TX", data, note);
}

async function sendWithOptionalAck(bytes, note, timeoutMs = 1700) {
  const arr = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes);
  const frameType = arr[0];
  const expectsAck = arr.length >= 2 && (frameType === 0x05 || frameType === 0x06);
  const cmdId = expectsAck ? arr[1] : null;
  let ackPromise = null;
  if (expectsAck && cmdId != null) {
    ackPromise = queueAck(cmdId, timeoutMs);
  }
  await writeTx(arr, note);
  if (!ackPromise) {
    return { state: "none" };
  }
  return ackPromise;
}

async function runSave(saveKey, bytes, note) {
  const payloadHex = bytesToHex(bytes);
  try {
    const result = await sendWithOptionalAck(bytes, note);
    if (result.state === "acknowledged") {
      addSaveTrack(saveKey, payloadHex, "ACK");
      return;
    }
    if (result.state === "timeout") {
      addSaveTrack(saveKey, payloadHex, "NO_ACK");
      return;
    }
    if (result.state === "rejected") {
      addSaveTrack(saveKey, payloadHex, "REJECTED", `status=${result.ackStatus}`);
      return;
    }
    addSaveTrack(saveKey, payloadHex, "SENT");
  } catch (error) {
    addSaveTrack(saveKey, payloadHex, "FAILED", String(error));
    throw error;
  }
}

function getNumberInput(input, label) {
  const v = Number.parseFloat(input.value);
  if (!Number.isFinite(v)) {
    throw new Error(`Invalid value for ${label}`);
  }
  return v;
}

function getIntInput(input, label) {
  const v = Number.parseInt(input.value, 10);
  if (!Number.isFinite(v)) {
    throw new Error(`Invalid value for ${label}`);
  }
  return v;
}

async function handleAction(action) {
  switch (action) {
    case "output_on":
      await runSave("output_on", buildFrame06Int(0x0c, 0), "current_output_open");
      return;
    case "output_off":
      await runSave("output_off", buildFrame06Int(0x0c, 1), "current_output_close");
      return;
    case "manual_open":
      await runSave("manual_control", buildFrame06Int(0x23, 1), "manual_output_open");
      return;
    case "manual_close":
      await runSave("manual_control", buildFrame06Int(0x23, 0), "manual_output_close");
      return;
    case "keepalive_once":
      await writeTx(Uint8Array.from([0x02, 0x06, 0x06]), "keepalive");
      return;
    case "charging_stats_zero":
      await runSave(
        "charging_statistics_zero",
        buildFrame06Int(0x13, 0),
        "charging_statistics_zero",
      );
      return;
    case "set_output_voltage": {
      const value = getNumberInput(dom.setVoltage, "output voltage");
      await runSave(
        "output_current_voltage",
        buildFrame06Float(0x07, value),
        "output_voltage_setpoint",
      );
      return;
    }
    case "set_output_current": {
      const value = getNumberInput(dom.setCurrent, "output current");
      await runSave(
        "output_current_limit",
        buildFrame06Float(0x08, value),
        "output_current_setpoint",
      );
      return;
    }
    case "set_power_off_current": {
      const value = getNumberInput(dom.powerOffCurrent, "power off current");
      await runSave("power_off_current", buildFrame06Float(0x15, value), "power_off_current");
      return;
    }
    case "set_stage2_voltage": {
      const value = getNumberInput(dom.stage2Voltage, "stage2 voltage");
      await runSave("second_stage_voltage", buildFrame06Float(0x21, value), "stage2_voltage");
      return;
    }
    case "set_stage2_current": {
      const value = getNumberInput(dom.stage2Current, "stage2 current");
      await runSave("second_stage_current", buildFrame06Float(0x22, value), "stage2_current");
      return;
    }
    case "set_soft_start": {
      const value = getIntInput(dom.softStart, "soft start");
      await runSave("soft_start_time", buildFrame06Int(0x26, value), "soft_start_time");
      return;
    }
    case "set_power_limit": {
      const value = getIntInput(dom.powerLimit, "power limit");
      await runSave("power_limit", buildFrame06Int(0x27, value), "power_limit_watts");
      return;
    }
    case "save_power_on_output": {
      const selected = dom.powerOnOutput.value;
      const protocolValue = selected === "open" ? 0 : 1;
      await runSave("power_on_output", buildFrame06Int(0x0b, protocolValue), "power_on_output");
      return;
    }
    case "save_self_stop": {
      const selected = dom.selfStop.value;
      await runSave("self_stop", buildFrame06Int(0x14, selected === "on" ? 1 : 0), "self_stop");
      return;
    }
    case "save_two_stage": {
      const selected = dom.twoStage.value;
      await runSave(
        "two_stage_switch",
        buildFrame06Int(0x20, selected === "on" ? 1 : 0),
        "two_stage_switch",
      );
      return;
    }
    case "save_multi_motor": {
      const selected = dom.multiMotor.value;
      await runSave(
        "multi_motor_current_mode",
        buildFrame06Int(0x2f, selected === "equal" ? 1 : 0),
        "multi_motor_mode",
      );
      return;
    }
    case "save_language": {
      const selected = dom.displayLanguage.value;
      const bytes = (() => {
        if (selected === "chinese_simplified") {
          return buildFrame05FromBytes(0x2a, 0x7a, 0x68, 0x00); // "zh"
        }
        if (selected === "chinese_traditional") {
          return buildFrame05FromBytes(0x2a, 0x7a, 0x74, 0x00); // "zt" candidate
        }
        return buildFrame05FromBytes(0x2a, 0x65, 0x6e, 0x00); // "en"
      })();
      await runSave("display_language", bytes, "display_language");
      return;
    }
    case "save_name": {
      const value = String(dom.chargerName.value || "");
      if (!value.trim()) {
        throw new Error("Charger name cannot be empty");
      }
      await runSave("safety_bluetooth_name", buildFrameAscii(0x1e, value, 16), "rename_charger_candidate");
      return;
    }
    case "save_password": {
      const value = String(dom.blePassword.value || "");
      if (!value.trim()) {
        throw new Error("Password cannot be empty");
      }
      await runSave(
        "safety_change_password",
        buildFrameAscii(0x1b, value, 16),
        "set_ble_password_candidate",
      );
      return;
    }
    default:
      throw new Error(`Unknown action: ${action}`);
  }
}

function clearKeepaliveLoop() {
  if (state.keepaliveTimer != null) {
    window.clearInterval(state.keepaliveTimer);
    state.keepaliveTimer = null;
  }
}

function startKeepaliveLoop() {
  clearKeepaliveLoop();
  const everyMs = Math.max(200, Number.parseInt(dom.keepaliveMs.value, 10) || 1000);
  dom.keepaliveMs.value = String(everyMs);
  state.keepaliveTimer = window.setInterval(async () => {
    if (!state.device || !state.device.gatt || !state.device.gatt.connected) {
      clearKeepaliveLoop();
      dom.keepaliveEnabled.checked = false;
      return;
    }
    try {
      await writeTx(Uint8Array.from([0x02, 0x06, 0x06]), "keepalive_loop");
    } catch (error) {
      console.error(error);
      clearKeepaliveLoop();
      dom.keepaliveEnabled.checked = false;
    }
  }, everyMs);
}

async function sendRawHex() {
  const bytes = hexToBytes(dom.rawHex.value);
  if (!bytes) {
    throw new Error("Invalid raw hex");
  }
  await runSave("raw_hex", bytes, "raw_hex");
}

function handleDisconnected() {
  clearKeepaliveLoop();
  dom.keepaliveEnabled.checked = false;
  setConnectionState(false);
  setMessage("Disconnected");
  state.server = null;
  state.rxChar = null;
  state.txChar = null;
  dom.rxUuid.textContent = "-";
  dom.txUuid.textContent = "-";
}

async function connectDevice() {
  if (!navigator.bluetooth) {
    throw new Error("Web Bluetooth is not available in this browser");
  }
  const device = await navigator.bluetooth.requestDevice({
    acceptAllDevices: true,
    optionalServices: [UUIDS.ffe1, UUIDS.ffe2, UUIDS.ffe3],
  });
  if (state.device && state.device !== device) {
    state.device.removeEventListener("gattserverdisconnected", handleDisconnected);
  }
  state.device = device;
  state.device.addEventListener("gattserverdisconnected", handleDisconnected);
  setDeviceName(device.name || device.id);
  state.server = await device.gatt.connect();
  await discoverCharacteristics();
  setConnectionState(true);
  setMessage(device.name || "Connected");
}

async function disconnectDevice() {
  clearKeepaliveLoop();
  dom.keepaliveEnabled.checked = false;
  if (state.device && state.device.gatt && state.device.gatt.connected) {
    state.device.gatt.disconnect();
  }
  handleDisconnected();
}

async function rediscover() {
  ensureConnected();
  await discoverCharacteristics();
  setMessage("Services rediscovered");
}

function init() {
  setConnectionState(false);
  renderCounters();
  renderLogs();
  renderSaveTrack();
  renderTelemetry();

  if (!navigator.bluetooth) {
    setMessage("Web Bluetooth unavailable. Use desktop Chrome/Edge on localhost.");
  }

  dom.connectBtn.addEventListener("click", async () => {
    try {
      await connectDevice();
    } catch (error) {
      console.error(error);
      setMessage(`Connect failed: ${String(error.message || error)}`);
    }
  });

  dom.disconnectBtn.addEventListener("click", async () => {
    try {
      await disconnectDevice();
    } catch (error) {
      console.error(error);
      setMessage(`Disconnect failed: ${String(error.message || error)}`);
    }
  });

  dom.discoverBtn.addEventListener("click", async () => {
    try {
      await rediscover();
    } catch (error) {
      console.error(error);
      setMessage(`Rediscover failed: ${String(error.message || error)}`);
    }
  });

  dom.sendRawBtn.addEventListener("click", async () => {
    try {
      await sendRawHex();
    } catch (error) {
      console.error(error);
      setMessage(`Raw send failed: ${String(error.message || error)}`);
    }
  });

  document.querySelectorAll("[data-action]").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = button.getAttribute("data-action");
      if (!action) {
        return;
      }
      try {
        await handleAction(action);
      } catch (error) {
        console.error(error);
        setMessage(`${action} failed: ${String(error.message || error)}`);
      }
    });
  });

  dom.keepaliveEnabled.addEventListener("change", () => {
    if (dom.keepaliveEnabled.checked) {
      startKeepaliveLoop();
      return;
    }
    clearKeepaliveLoop();
  });
}

init();

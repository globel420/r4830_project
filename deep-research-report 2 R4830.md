# Deep research on controlling the Hou NIN “Fast Smart Charger” / Huawei R48xx touchscreen Bluetooth CAN controller over BLE

## Research scope and methodology

This research targeted **publicly available** material that could document how to control the Hou NIN “Fast Smart Charger” (often described as a modified Huawei R48xx telecom rectifier setup) via **Bluetooth Low Energy**: source repos, protocol write-ups, firmware notes, GATT dumps, packet captures, APKs, and reverse‑engineering threads. citeturn35search3turn32search7turn32search1

The public web results clustered into two buckets:

- **Product / marketing pages** (Hou Nin EUC Club, Pidzoom) describing features like app control, “auto stop”, and multi‑stage charging—useful as UI/feature hints but not protocol details. citeturn33search9turn33search2  
- **Community threads** (EUC forums) that provide the most actionable lead: **where the Android APKs are hosted**, and that **EUC World** can directly control “HW charger” BLE chargers (suggesting a stable shared BLE protocol across brands). citeturn35search0turn35search3  

Critically, I did **not** find any public, credible sources that already publish:
- a full **GATT handle/UUID map** for this charger family,  
- a complete **telemetry field offset table**, or  
- a written **authentication success/failure** response mapping.

The closest “protocol-adjacent” public information is: (a) app distribution links and (b) a general BLE-module article explaining how FFE1/FFE2/FFE3 are commonly used in some Chinese BLE modules—useful as a pattern match, not device-specific proof. citeturn35search0turn36search4  

## What the open web documents about these chargers

Public sources consistently frame these chargers as **telecom power supplies adapted for personal EV / EUC charging**, with newer versions featuring a color touchscreen and Bluetooth app control. citeturn35search3turn33search9turn33search2

The most concrete public breadcrumbs that matter for BLE reverse engineering are:

- Multiple sellers point to an **Android app download** (binary APK) and an **iOS path via Alipay**, implying a shared or reused software stack. citeturn33search9turn33search2turn28search2  
- EUC World explicitly claims **“nearly full support”** for BT-enabled fast chargers like **Pidzoom HW170P** and **Roger Charger V4SC**, and says it “should also work” with **Hou Nin 4815G2 / HW R4875** models—strong evidence that the ecosystem converges on a common BLE control protocol (even if undocumented). citeturn35search3  
- A French forum post aggregates links to multiple APKs (Hou Nin, Roger) and documents the in-app path to connect as “HW charger” → “ch1” in EUC World, which is useful for identifying device naming conventions and app-side abstractions. citeturn35search0turn35search3  

image_group{"layout":"carousel","aspect_ratio":"16:9","query":["Hou Nin touch screen fast smart charger 2500W","Hou Nin 5000W touch screen fast smart charger","Pidzoom HW170P fast charger","Huawei R4875G1 rectifier module"],"num_per_query":1}

## Ranked source list with direct links and gap analysis

Below is a ranked list of the best public sources found, ordered by how directly they advance BLE protocol reverse engineering (apps/repos/docs > forum threads with links > product pages).

1. **EUC World 2.52.3 release announcement (BT-enabled fast charger support)**  
   Link: `https://euc.world/blog/euc-world-2-52-3-has-been-released` citeturn35search3  
   What it contains: confirms direct BLE control of “BT-enabled fast chargers”; identifies this charger class as modified telecom PSUs; names verified chargers (Pidzoom HW170P, Roger Charger V4SC) and claims likely compatibility with Hou Nin models. citeturn35search3  
   Credibility: high for feature claims (first-party app blog). citeturn35search3  
   Gaps: no GATT UUID/handle map, no packet formats, no telemetry field layout, no auth protocol details. citeturn35search3  

2. **EspritRoue forum thread aggregating charger apps + EUC World connection steps**  
   Link: `https://www.espritroue.fr/topic/24824-quel-chargeur-rapide-choisir/page/2/` citeturn35search0  
   What it contains: concrete workflow (“charging control” → “device” → “HW charger” → scan → select “ch1”), plus direct APK link for a Hou Nin app hosted on a GitHub releases URL, and references to a Roger app via Telegram and iOS TestFlight. citeturn35search0  
   Credibility: medium (community post), but it links to primary artifacts (APKs / official blog). citeturn35search0turn35search3  
   Gaps: does not document protocol internals; APK links are the real value. citeturn35search0  

3. **niub.cc “HW智能充电器APP下载 / HW48系列蓝牙控制板” page**  
   Link: `https://www.niub.cc/index/article/detail/id/2.html` citeturn28search2  
   What it contains: states “HW48 series Bluetooth control board” for Huawei 4850/4875 and provides an APP download button + iOS path via Alipay. citeturn28search2turn12view0  
   Credibility: medium; it looks like a vendor/landing page and is directly on-topic. citeturn28search2  
   Gaps: the BLE protocol is not described; the download endpoint is opaque (“点击下载”). citeturn28search2turn13view0  

4. **Hou Nin EUC Club product pages (feature + app download pointers)**  
   Example links:  
   - `https://houeuc.com/product/2500w-mini-touch-screen-fast-smart-charger/` citeturn33search9  
   - `https://houeuc.com/product/5000w-touch-screen-fast-smart-charger/` citeturn33search4  
   What they contain: standardized “settings” description (Auto Stop, Out SW, brightness, “connect to app”) and iOS via Alipay mention. citeturn33search9turn33search4  
   Credibility: medium; commerce pages, but consistent and useful for inferring which parameters must exist in the BLE protocol. citeturn33search9  
   Gaps: no actual protocol data (UUIDs/handles/frames). citeturn33search9  

5. **Pidzoom product pages (feature + app download pointers)**  
   Example link: `https://pidzoom.com/products/fast-charger-portable-sc` citeturn33search2  
   What it contains: similar settings description and explicit iOS via Alipay mention. citeturn33search2  
   Most actionable artifact: the Android APK appears to be hosted at a Shopify CDN URL (binary). citeturn23view0  
   Credibility: medium-high as a vendor storefront describing real shipped behavior. citeturn33search2  
   Gaps: still no protocol docs; protocol extraction requires APK reverse engineering. citeturn33search2turn23view0  

6. **ElectricUnicycle forum thread pointing to the niub.cc app**  
   Link: `https://forum.electricunicycle.org/topic/39355-rogers-sc-charger-the-best-ev-charger-ever/` citeturn11view0  
   What it contains: community discussion + a pointer to the niub.cc HW smart charger app page. citeturn11view0turn12view0  
   Credibility: medium (community forum), valuable mostly as corroboration and link discovery. citeturn11view0  
   Gaps: no BLE/GATT content. citeturn11view0  

7. **Elecfans JDY-24M BLE module article describing FFE1/FFE2/FFE3 usage**  
   Link: `https://www.elecfans.com/d/6816675.html` citeturn36search4  
   What it contains: a general explanation that some BLE modules expose service/characteristics around UUIDs like FFE1/FFE2/FFE3, where FFE1/FFE2 are used for transparent transmission and FFE3 for mesh/config/data. citeturn36search4  
   Credibility: medium for the module it documents; **not charger-specific**, but it strongly matches the UUID pattern in your ground truth and helps generate realistic “what to grep for” targets inside APKs. citeturn36search4  
   Gaps: not a charger protocol; can’t be treated as authoritative for this device family. citeturn36search4  

8. **RFC 1321 (MD5) test suite reference**  
   Link: `https://www.rfc-editor.org/rfc/rfc1321` citeturn37search0  
   What it contains: the formal MD5 algorithm reference; the test suite (“MD5(\"\") = d41d8cd…”) is useful for validating whether observed password payloads are MD5-based. citeturn37search7turn37search0  
   Credibility: very high (RFC Editor). citeturn37search0  
   Gaps: not device-specific; only supports the cryptographic identification step. citeturn37search0  

## Protocol reconstruction from captures and cross-checks

This section focuses on what can be **reliably** derived from your provided capture artifacts (btsnoop payload lists) and ties it back to the public breadcrumbs above. The goal is to reduce the unknown space before APK teardown.

### Observed write path and frame families

Your btsnoop-based extraction shows that outbound writes are ATT **Write Command** (opcode `0x52`) targeting **handle `0x0006`**, and that many payloads are compact framed messages (including the 0x06-prefixed “register write” family and ASCII-heavy password-related traffic). fileciteturn3file6L1-L14

Two high-confidence frame families present in your extracted payloads are:

- **Register write frames (“06 …”)**: `LEN_MINUS_1 | CMD_ID | 4-byte LE value | CHECKSUM` (7 bytes total for 4-byte values). These appear repeatedly during parameter changes. fileciteturn3file6L8-L24  
- **ASCII command frames** for rename and other short strings: e.g., `0x0D 0x1E "ChargeFast" 0x00 CHK` and `0x0A 0x1E "go slow" 0x00 CHK`. fileciteturn3file6L41-L44  

The checksum behavior is consistent with:  
**CHK = (CMD_ID + sum(DATA_BYTES)) & 0xFF**, and the leading byte behaves as **LEN-1** (i.e., total bytes excluding itself), matching the rename frames’ length behavior. fileciteturn3file6L41-L44  

### Recovered command/register table from your captures

The table below consolidates (a) your confirmed IDs and (b) additional IDs that appear in your payload extracts.

These are all **phone → charger writes** observed on handle `0x0006`. fileciteturn3file6L1-L24

| CMD ID | Payload type | Evidence in captures | Interpreted meaning (confidence) |
|---|---|---|---|
| `0x07` | float32 LE | Values decode to realistic voltages (e.g., 147–151). fileciteturn3file6L12-L20 | Output voltage setpoint (high; matches your ground truth). |
| `0x08` | float32 LE | Values include 0.5, 1.0, etc. fileciteturn3file6L29-L33 | Output current setpoint (high; matches your ground truth). |
| `0x0C` | uint32 LE (bool) | `…01000000…` and `…00000000…` forms. fileciteturn3file6L8-L12 | “Current path” enable/disable (high; matches your ground truth). |
| `0x15` | float32 LE | Seen values decode to plausible “auto stop current threshold” numbers (e.g., 0.3, 1, 5, 8, 9). fileciteturn3file6L15-L28 | Power‑off current threshold / stop condition (high; matches your ground truth). |
| `0x21` | float32 LE | Multiple voltage-like values (e.g., 149, 150, 151). fileciteturn8file4L23-L29 | Stage 2 voltage target (high; matches your ground truth). |
| `0x22` | float32 LE | Values like 0.5, 0.8, 1.0 appear. fileciteturn8file0L26-L29 | Stage 2 current target (high; matches your ground truth). |
| `0x23` | uint32 LE (bool) | `…00000000…` and `…01000000…` forms. fileciteturn3file6L13-L15 | Manual output open/close (high; matches your ground truth). |
| `0x26` | uint32 LE | Values include 1, 5, 8. fileciteturn3file6L21-L23 | Soft-start time seconds (high; matches your ground truth). |
| `0x2F` | uint32 LE (bool) | `0` and `1` forms appear. fileciteturn3file6L20-L23 | Current distribution mode equal/intelligent (high; matches your ground truth). |
| `0x1E` | ASCII + NUL | Rename examples: “ChargeFast”, “go slow”. fileciteturn3file6L41-L44 | Device name change (high; matches your ground truth). |
| `0x2A` | ASCII + NUL | `en` and `zh` payloads appear around a “changed language” label. fileciteturn7file0L224-L233 | Language setting (medium-high; strong evidence from payload content and capture label). |
| `0x20` | uint32 LE (bool) | Observed as `0` / `1` toggles. fileciteturn7file0L27-L29 | Likely a mode toggle (medium). **Caution:** although one local “dictionary” labels `0x20` as “Stage 1 Current”, the observed wire values are integer toggles (`0/1`), not float32 current. fileciteturn7file0L27-L29turn6file0L129-L135 |
| `0x0B`, `0x13`, `0x14` | uint32 LE (bool) | Seen toggling patterns. fileciteturn7file0L31-L35 | Unknown flags (medium-low). Candidate mapping: `0x0B` may correlate with “Auto Stop” mentioned in product pages, but no direct proof from public sources. citeturn33search9turn33search2 |

### Authentication/password protocol: MD5 evidence in payloads

Your “password exercise” capture (switching from no password → `p2468` → `p1357` → `pass` → wrong password `pazz` → back to no password) includes repeated long ASCII-hex strings written to handle `0x0006`, including:

- `D41D8CD98F00B204E9...800998ECF8427E...` (widely known as the MD5 of an empty string) fileciteturn8file1L12-L18  
- `A06CA4B4BE9C0710FDA22C1A57E23110` fileciteturn8file1L31-L40  
- `3C885DDFB0E94CCA5227672676BFE46A` fileciteturn8file1L37-L40  
- `1A1DC91C907325C69271DDF0C944BC72` fileciteturn8file1L53-L55  
- `014877E71841E82D44CE524D66DCC732` fileciteturn8file1L39-L41  

The MD5 test suite in RFC 1321 includes the canonical empty-string digest `d41d8cd98f00b204e9800998ecf8427e`, supporting the identification that the “no password” state is represented on-wire by an MD5 digest value. citeturn37search7turn37search0  

**Most defensible conclusion:** the password/auth flow uses an **MD5 digest of the user-entered password** (and likely transmits it in ASCII hex, sometimes split across multiple frames/prefixes like `0x23 0x02 …` and `0x4A 0x03 …`). fileciteturn8file1L31-L40turn8file1L53-L55  

**What is still not decoded from available data:** explicit **success/failure response frames** (e.g., a notify/indicate payload proving “auth OK/NO”), because the extracted list you provided is focused on outbound writes and doesn’t include a clearly identified inbound response series. fileciteturn3file6L1-L14  

## What remains missing and how to close the gaps

### Missing items not found in public sources

The following items were not found as published tables/dumps in the sources above (repos/forums/vendor pages):

- **Full GATT map** (exact characteristic UUIDs and handles; which characteristic is notify vs write). Public sources discuss “Bluetooth control,” but provide no GATT specifics. citeturn33search9turn35search3turn35search0  
- **Telemetry decoding table** (field offsets/scaling for voltage/current/power/temps/errors/stats). EUC World claims it can display charging parameters and graphs, but does not publish the underlying spec. citeturn35search3  
- **Documented auth success/fail responses**. No public protocol write-up was found; the best evidence comes from your captured MD5-like exchanged values. fileciteturn8file1L31-L40  

### Best next steps that are most likely to succeed

The public web strongly suggests the protocol is implemented in distributed apps (Hou Nin / Pidzoom / “HW智能充电器” / Roger). That makes APK teardown the highest-yield path.

Concrete artifact targets discovered in public sources:

- Hou Nin-linked APK (GitHub release URL as posted in EspritRoue):  
  `https://github.com/muzk6/houeuc.com/releases/download/0.1.0/hounin_fast_charger_app.apk` citeturn35search0  
- Pidzoom Android APK (Shopify CDN URL referenced by the vendor page’s Download button):  
  `https://cdn.shopify.com/s/files/1/0641/1365/1369/files/PIDZOOM_fast_charger_App_APK.apk?v=1684999464` citeturn23view0  
- niub.cc HW smart charger app landing page (download button present):  
  `https://www.niub.cc/index/article/detail/id/2.html` citeturn28search2  

For reverse-engineering those APKs, the shortest path to the missing info is:

- **GATT map recovery**: grep decompiled code for `FFE1`, `FFE2`, `FFE3`, `0000ffe` patterns, and any 128‑bit UUID strings. Cross-check against a known pattern where some BLE modules use **FFE1/FFE2 for transparent data** and **FFE3 for config/data**, as documented for JDY-24M-style modules. citeturn36search4  
- **Command builder confirmation**: search for byte array construction containing your known CMD IDs (`0x07`, `0x08`, `0x0C`, `0x15`, `0x21`, `0x22`, `0x23`, `0x26`, `0x2F`, `0x1E`, `0x2A`), and for checksum code matching an 8-bit sum. fileciteturn3file6L8-L24  
- **Auth protocol completion**: search for `MD5` usage (common Java patterns like `MessageDigest.getInstance("MD5")`) and identify whether the app uses plain MD5(password) or MD5(password + salt/challenge). Your captures already show MD5-shaped values and the empty-string MD5 for the no-password case. fileciteturn8file1L12-L18turn8file1L53-L55turn37search7  
- **Telemetry table extraction**: look for code that parses incoming byte buffers from the notify/indicate characteristic (likely your “FFE2 telemetry” path). Useful search anchors: `ByteBuffer`, `getFloat`, `getInt`, `Endian.LITTLE`, array slicing, and UI labels like “temp”, “fault”, “alarm”, “output”, “fan”, “CAN”, “rectifier”, “module”. citeturn35search3turn33search9  

Finally, if your device’s UUID set is indeed FFE1/FFE2/FFE3, the JDY‑24M documentation is a good heuristic for what to expect in a generic BLE stack: it explicitly describes selecting UUIDs FFE1/FFE2 for data transfer and UUID FFE3 for control/config in some module/app ecosystems—useful for narrowing where telemetry vs command code will live inside the APK. citeturn36search4
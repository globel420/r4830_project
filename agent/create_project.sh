#!/bin/bash

# This script creates the ChargeFast Controller Flutter project and populates it with the generated code.

# Please ensure you have Flutter installed and configured in your PATH.
# If flutter is not in your path, you can modify the FLUTTER_CMD variable below.
FLUTTER_CMD="flutter"

PROJECT_NAME="chargefast_controller_app"
PROJECT_DIR="../controller/$PROJECT_NAME"

echo "Creating Flutter project in $PROJECT_DIR..."
$FLUTTER_CMD create "$PROJECT_DIR"

echo "Creating project structure..."
mkdir -p "$PROJECT_DIR/lib/models"
mkdir -p "$PROJECT_DIR/lib/services"
mkdir -p "$PROJECT_DIR/lib/presentation/screens"
mkdir -p "$PROJECT_DIR/lib/presentation/widgets"
mkdir -p "$PROJECT_DIR/assets"

echo "Copying generated files..."
cp "generated_code/pubspec.yaml" "$PROJECT_DIR/"
cp "generated_code/lib/models/ble_definitions.dart" "$PROJECT_DIR/lib/models/"
cp "generated_code/lib/services/ble_definitions_service.dart" "$PROJECT_DIR/lib/services/"
cp "generated_code/lib/services/ble_controller_service.dart" "$PROJECT_DIR/lib/services/"
cp "generated_code/lib/main.dart" "$PROJECT_DIR/lib/"
cp "generated_code/lib/presentation/screens/home_screen.dart" "$PROJECT_DIR/lib/presentation/screens/"
cp "generated_code/lib/presentation/screens/device_control_screen.dart" "$PROJECT_DIR/lib/presentation/screens/"
cp "generated_code/lib/presentation/widgets/toggle_widget.dart" "$PROJECT_-DIR/lib/presentation/widgets/"
cp "generated_code/lib/presentation/widgets/selector_widget.dart" "$PROJECT_DIR/lib/presentation/widgets/"

echo "Copying assets..."
cp "ble_definitions.yaml" "$PROJECT_DIR/assets/"

echo "Adding platform permissions..."

# iOS permissions
PLIST_FILE="$PROJECT_DIR/ios/Runner/Info.plist"
if [ -f "$PLIST_FILE" ]; then
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string 'This app needs Bluetooth to connect to the ChargeFast device.'" "$PLIST_FILE"
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothPeripheralUsageDescription string 'This app needs Bluetooth to connect to the ChargeFast device.'" "$PLIST_FILE"
else
    echo "Info.plist not found, skipping iOS permissions."
fi

# macOS permissions
MACOS_DEBUG_ENTITLEMENTS="$PROJECT_DIR/macos/Runner/DebugProfile.entitlements"
MACOS_RELEASE_ENTITLEMENTS="$PROJECT_DIR/macos/Runner/Release.entitlements"

if [ -f "$MACOS_DEBUG_ENTITLEMENTS" ]; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$MACOS_DEBUG_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.device.bluetooth bool true" "$MACOS_DEBUG_ENTITLEMENTS"
else
    echo "DebugProfile.entitlements not found, skipping macOS debug permissions."
fi

if [ -f "$MACOS_RELEASE_ENTITLEMENTS" ]; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$MACOS_RELEASE_ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.device.bluetooth bool true" "$MACOS_RELEASE_ENTITLEMENTS"
else
    echo "Release.entitlements not found, skipping macOS release permissions."
fi

echo "Project setup complete!"
echo "You can now open the project in '$PROJECT_DIR' and run it."

#!/bin/bash
#
# build.sh - Build script for BetterFasterWhisper
#
# This script builds both the Rust whisper-core library and the Swift application.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/whisper-core"
APP_DIR="$PROJECT_ROOT/App"
BUILD_TYPE="${1:-debug}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  BetterFasterWhisper Build Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check for required tools
check_requirements() {
    echo -e "${YELLOW}Checking requirements...${NC}"
    
    # Check Rust
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}Error: Rust/Cargo not found.${NC}"
        echo "Please install Rust: https://rustup.rs/"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Rust $(rustc --version | cut -d' ' -f2)"
    
    # Check Swift
    if ! command -v swift &> /dev/null; then
        echo -e "${RED}Error: Swift not found.${NC}"
        echo "Please install Xcode Command Line Tools."
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Swift $(swift --version | head -1 | cut -d' ' -f4)"
    
    # Check for Apple Silicon
    ARCH=$(uname -m)
    echo -e "  ${GREEN}✓${NC} Architecture: $ARCH"
    
    echo ""
}

# Build Rust library
build_rust() {
    echo -e "${YELLOW}Building Rust whisper-core...${NC}"
    cd "$RUST_DIR"
    
    if [ "$BUILD_TYPE" = "release" ]; then
        cargo build --release
        echo -e "  ${GREEN}✓${NC} Built release library"
    else
        cargo build
        echo -e "  ${GREEN}✓${NC} Built debug library"
    fi
    
    # Copy header to Swift bridge
    if [ -f "include/whisper_core.h" ]; then
        cp include/whisper_core.h "$APP_DIR/WhisperBridge/include/"
        echo -e "  ${GREEN}✓${NC} Copied C header"
    fi
    
    echo ""
}

# Build Swift application
build_swift() {
    echo -e "${YELLOW}Building Swift application...${NC}"
    cd "$PROJECT_ROOT"
    
    if [ "$BUILD_TYPE" = "release" ]; then
        swift build -c release
        echo -e "  ${GREEN}✓${NC} Built release application"
    else
        swift build
        echo -e "  ${GREEN}✓${NC} Built debug application"
    fi
    
    echo ""
}

# Create app bundle
create_bundle() {
    echo -e "${YELLOW}Creating app bundle...${NC}"
    
    BUNDLE_DIR="$PROJECT_ROOT/build/BetterFasterWhisper.app"
    CONTENTS_DIR="$BUNDLE_DIR/Contents"
    MACOS_DIR="$CONTENTS_DIR/MacOS"
    RESOURCES_DIR="$CONTENTS_DIR/Resources"
    FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
    
    # Create directories
    mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
    
    # Copy executable
    if [ "$BUILD_TYPE" = "release" ]; then
        BUILD_DIR="$PROJECT_ROOT/.build/release"
    else
        BUILD_DIR="$PROJECT_ROOT/.build/debug"
    fi
    
    if [ -f "$BUILD_DIR/BetterFasterWhisper" ]; then
        cp "$BUILD_DIR/BetterFasterWhisper" "$MACOS_DIR/"
        echo -e "  ${GREEN}✓${NC} Copied executable"
    fi
    
    # Copy Rust library
    RUST_LIB_DIR="$RUST_DIR/target/${BUILD_TYPE}"
    if [ -f "$RUST_LIB_DIR/libwhisper_core.dylib" ]; then
        cp "$RUST_LIB_DIR/libwhisper_core.dylib" "$FRAMEWORKS_DIR/"
        echo -e "  ${GREEN}✓${NC} Copied Rust library"
    fi
    
    # Create Info.plist
    cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BetterFasterWhisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.betterfasterwhisper.app</string>
    <key>CFBundleName</key>
    <string>BetterFasterWhisper</string>
    <key>CFBundleDisplayName</key>
    <string>BetterFasterWhisper</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>BetterFasterWhisper needs microphone access to transcribe your speech.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>BetterFasterWhisper needs accessibility access to paste transcribed text.</string>
</dict>
</plist>
EOF
    echo -e "  ${GREEN}✓${NC} Created Info.plist"
    
    echo -e "${GREEN}App bundle created at: $BUNDLE_DIR${NC}"
    echo ""
}

# Main
main() {
    check_requirements
    
    # Build Rust (optional - skip if cargo not available)
    if command -v cargo &> /dev/null; then
        build_rust
    else
        echo -e "${YELLOW}Skipping Rust build (cargo not found)${NC}"
    fi
    
    # Build Swift
    build_swift
    
    # Create bundle
    create_bundle
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Build complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
}

main

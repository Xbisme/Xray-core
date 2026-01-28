#!/bin/bash

set -e

echo "🔨 Building xray-core for Android (FIXED VERSION)"
echo "=================================================="
echo ""

# Check NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "❌ ANDROID_NDK_HOME not set!"
    echo ""
    echo "Please set it first:"
    echo "  export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/YOUR_VERSION"
    echo ""
    exit 1
fi

# Detect NDK binary path
if [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64" ]; then
    NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64/bin"
    echo "✅ Detected Apple Silicon Mac (ARM64)"
elif [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64" ]; then
    NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    echo "✅ Detected Intel Mac (x86_64)"
else
    echo "❌ Cannot find NDK toolchain!"
    exit 1
fi

echo "📍 NDK: $ANDROID_NDK_HOME"
echo "🔧 Toolchain: $NDK_BIN"
echo ""

# ===== CRITICAL FIX =====
# Android requires specific build flags to avoid SIGSEGV
# We need to:
# 1. Use CGO (some Go features need it)
# 2. Link against Android's libc
# 3. Set proper page size for Android 15+
# 4. Use PIE (position independent executable)

# Clean previous builds
rm -rf jniLibs
mkdir -p jniLibs/arm64-v8a
mkdir -p jniLibs/armeabi-v7a
mkdir -p jniLibs/x86_64
mkdir -p jniLibs/x86

# Common Go flags
export CGO_ENABLED=1
export GOOS=android

# Build flags - CRITICAL for Android compatibility
LDFLAGS="-s -w -buildmode=pie -linkmode=external"
LDFLAGS="$LDFLAGS -extldflags=-Wl,-z,max-page-size=16384"
LDFLAGS="$LDFLAGS -extldflags=-static-libgcc"

# Tags to disable problematic features
TAGS="android"

echo "🔧 Build flags:"
echo "   LDFLAGS: $LDFLAGS"
echo "   TAGS: $TAGS"
echo ""

# ===== ARM64 (arm64-v8a) =====
echo "📱 [1/4] Building ARM64 (arm64-v8a)..."
export GOARCH=arm64
export CC="$NDK_BIN/aarch64-linux-android21-clang"
export CXX="$NDK_BIN/aarch64-linux-android21-clang++"

go build \
    -trimpath \
    -tags="$TAGS" \
    -ldflags="$LDFLAGS" \
    -o jniLibs/arm64-v8a/libxray.so \
    ./main

if [ $? -eq 0 ]; then
    echo "   ✅ ARM64 build successful"
    chmod +x jniLibs/arm64-v8a/libxray.so
else
    echo "   ❌ ARM64 build failed!"
    exit 1
fi

# ===== ARM32 (armeabi-v7a) =====
echo "📱 [2/4] Building ARM32 (armeabi-v7a)..."
export GOARCH=arm
export GOARM=7
export CC="$NDK_BIN/armv7a-linux-androideabi21-clang"
export CXX="$NDK_BIN/armv7a-linux-androideabi21-clang++"

go build \
    -trimpath \
    -tags="$TAGS" \
    -ldflags="$LDFLAGS" \
    -o jniLibs/armeabi-v7a/libxray.so \
    ./main

if [ $? -eq 0 ]; then
    echo "   ✅ ARM32 build successful"
    chmod +x jniLibs/armeabi-v7a/libxray.so
else
    echo "   ❌ ARM32 build failed!"
    exit 1
fi

# ===== x86_64 =====
echo "📱 [3/4] Building x86_64..."
export GOARCH=amd64
export CC="$NDK_BIN/x86_64-linux-android21-clang"
export CXX="$NDK_BIN/x86_64-linux-android21-clang++"

go build \
    -trimpath \
    -tags="$TAGS" \
    -ldflags="$LDFLAGS" \
    -o jniLibs/x86_64/libxray.so \
    ./main

if [ $? -eq 0 ]; then
    echo "   ✅ x86_64 build successful"
    chmod +x jniLibs/x86_64/libxray.so
else
    echo "   ❌ x86_64 build failed!"
    exit 1
fi

# ===== x86 =====
echo "📱 [4/4] Building x86..."
export GOARCH=386
export CC="$NDK_BIN/i686-linux-android21-clang"
export CXX="$NDK_BIN/i686-linux-android21-clang++"

go build \
    -trimpath \
    -tags="$TAGS" \
    -ldflags="$LDFLAGS" \
    -o jniLibs/x86/libxray.so \
    ./main

if [ $? -eq 0 ]; then
    echo "   ✅ x86 build successful"
    chmod +x jniLibs/x86/libxray.so
else
    echo "   ❌ x86 build failed!"
    exit 1
fi

echo ""
echo "📦 Verifying binaries..."
echo ""

for arch in arm64-v8a armeabi-v7a x86_64 x86; do
    echo "=== $arch ==="
    
    LIB_PATH="jniLibs/$arch/libxray.so"
    
    # File info
    file "$LIB_PATH"
    
    # Size
    ls -lh "$LIB_PATH"
    
    # Check if PIE
    echo -n "PIE Status: "
    if readelf -h "$LIB_PATH" 2>/dev/null | grep -q "Type:.*DYN"; then
        echo "✅ PIE (DYN)"
    elif readelf -h "$LIB_PATH" 2>/dev/null | grep -q "Type:.*EXEC"; then
        echo "❌ NOT PIE (EXEC) - Will crash on Android 5.0+"
    else
        echo "❓ Unknown"
    fi
    
    # Check dependencies
    echo "Dependencies:"
    readelf -d "$LIB_PATH" 2>/dev/null | grep NEEDED | head -5 || echo "  (none or error reading)"
    
    echo ""
done

echo "=========================================="
echo "✅ Build Complete!"
echo "=========================================="
echo ""
echo "📋 Next steps:"
echo "1. Test binary locally (optional):"
echo "   adb push jniLibs/arm64-v8a/libxray.so /data/local/tmp/"
echo "   adb shell /data/local/tmp/libxray.so version"
echo ""
echo "2. Deploy to Android project:"
echo "   ./deploy-to-android.sh /path/to/your/app"
echo ""
echo "📂 Output location: $(pwd)/jniLibs/"
echo ""

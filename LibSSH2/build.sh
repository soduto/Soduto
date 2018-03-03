set | grep ARCH
set -e
set -x

## Config

export SDK_VERSION=
export LIBSSH_VERSION=
export LIBSSL_VERSION=
export MIN_VERSION=
export ARCHS=
export SDK_PLATFORM=
export EMBED_BITCODE="-fembed-bitcode"

OSX_ARCHS="x86_64"
IOS_ARCHS="armv7 armv7s arm64"

BUILD_OSX=true
BUILD_SSL=false
BUILD_SSH=true
CLEAN_BUILD=true

if [[ -z "$MIN_VERSION" ]]; then
  if [[ $BUILD_OSX == true ]]; then
    MIN_VERSION="10.7"
  else
    MIN_VERSION="8.0"
  fi
fi

if [[ -z "$ARCHS" ]]; then
  if [[ $BUILD_OSX == true ]]; then
    ARCHS="$OSX_ARCHS"
  else
    ARCHS="$IOS_ARCHS $OSX_ARCHS"
  fi
fi

if [[ $BUILD_OSX == true ]]; then
  SDK_PLATFORM="macosx"
else
  SDK_PLATFORM="iphoneos"
fi

if [[ -z "$SDK_VERSION" ]]; then
   SDK_VERSION=`xcrun --sdk $SDK_PLATFORM --show-sdk-version`
fi

export BUILD_THREADS=$(sysctl hw.ncpu | awk '{print $2}')

export CLANG=`xcrun --find clang`
export GCC=`xcrun --find gcc`
export DEVELOPER=`xcode-select --print-path`

# source dir
export LIBSSHSRCDIR="$SRCROOT/libssh2"

# install dirs
export LIBSSLDIR="$TARGET_BUILD_DIR/openssl"
export LIBSSHDIR="$TARGET_BUILD_DIR/libssh2"

# check whether libssh2.a already exists - we'll only build if it does not
if [ -f  "$TARGET_BUILD_DIR/libssh2.a" ]; then
    echo "***** Using previously-built libary $TARGET_BUILD_DIR/libssh2.a - skipping build *****"
    echo "***** To force a rebuild clean project and clean dependencies *****"
    exit 0;
else
    echo "***** No previously-built libary present at $TARGET_BUILD_DIR/libssh2.a - performing build *****"
fi

if [ "$SDKROOT" != "" ]; then
    ISYSROOT="-isysroot $SDKROOT"
fi

echo "SRCROOT: $SRCROOT"
echo "BUILD_DIR: $BUILD_DIR"
echo "TARGET_BUILD_DIR: $TARGET_BUILD_DIR"
echo "libssh2 src: $LIBSSHSRCDIR"
echo "libssh2 install: $LIBSSHDIR"
echo "openssl install: $LIBSSLDIR"
echo "Architectures: $ARCHS"
echo "OS min version: $MIN_VERSION"
echo "ISYSROOT: $ISYSROOT"
echo

cd "$LIBSSHSRCDIR"

./buildconf >/dev/null 2>/dev/null

for ARCH in $ARCHS
    do
    echo "***** BUILDING UNIVERSAL ARCH $ARCH ******"

    if [[ "$ARCH" == "arm64" ]]; then
        HOST="aarch64-apple-darwin"
    else
        HOST="$ARCH-apple-darwin"
    fi

    export DEVROOT="$DEVELOPER/Platforms/$PLATFORM.platform/Developer"
    export SDKROOT="$DEVROOT/SDKs/$PLATFORM$SDK_VERSION.sdk"
    export CC="$CLANG"
    export CPP="$CLANG -E"
    export CFLAGS="-arch $ARCH -pipe -no-cpp-precomp $ISYSROOT -m$SDK_PLATFORM-version-min=$MIN_VERSION $EMBED_BITCODE"
    export CPPFLAGS="-arch $ARCH -pipe -no-cpp-precomp $ISYSROOT -m$SDK_PLATFORM-version-min=$MIN_VERSION"

    ./Configure --host=$HOST --prefix="$LIBSSHDIR" --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-examples-build --with-libz --with-openssl --with-libssl-prefix="$LIBSSLDIR" --disable-shared --enable-static

    make clean
    make 
    make -j "$BUILD_THREADS" install

    echo "***** copying intermediate libraries to $CONFIGURATION_TEMP_DIR/$ARCH-*.a *****"
    cp "$LIBSSHDIR/lib/libssh2.a" "$CONFIGURATION_TEMP_DIR"/$ARCH-libssh2.a

    echo "- $PLATFORM $ARCH done!"
done

echo "***** creating universallibraries in $TARGET_BUILD_DIR *****"
mkdir -p "$TARGET_BUILD_DIR"
lipo -create "$CONFIGURATION_TEMP_DIR/"*-libssh2.a -output "$TARGET_BUILD_DIR/libssh2.a"

echo "***** removing temporary files from $CONFIGURATION_TEMP_DIR *****"
rm -f "$CONFIGURATION_TEMP_DIR/"*-libssh2.a

echo "***** executing ranlib on libraries in $TARGET_BUILD_DIR *****"
ranlib "$TARGET_BUILD_DIR/libssh2.a"

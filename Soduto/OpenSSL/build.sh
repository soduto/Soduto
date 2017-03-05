set | grep ARCH
set -e
set -x

## Determine the appropriate openssl source path to use
## Introduced by michaeltyson, adapted to account for OPENSSL_SRC build path

OPENSSL_SRC="$SRCROOT/openssl"

# target install location
OPENSSLDIR="$TARGET_BUILD_DIR/openssl"

echo "***** using $OPENSSL_SRC for openssl source code  *****"

# check whether libcrypto.a already exists - we'll only build if it does not
if [ -f  "$TARGET_BUILD_DIR/libcrypto.a" ]; then
    echo "***** Using previously-built libary $TARGET_BUILD_DIR/libcrypto.a - skipping build *****"
    echo "***** To force a rebuild clean project and clean dependencies *****"
    exit 0;
else
    echo "***** No previously-built libary present at $TARGET_BUILD_DIR/libcrypto.a - performing build *****"
fi

# figure out the right set of build architectures for this run
#BUILDARCHS="$ARCHS"
BUILDARCHS="x86_64"

echo "***** creating universal binary for architectures: $BUILDARCHS *****"

if [ "$SDKROOT" != "" ]; then
    ISYSROOT="-isysroot $SDKROOT"
fi

echo "***** using ISYSROOT $ISYSROOT *****"

OPENSSL_OPTIONS="no-gost"

echo "***** using OPENSSL_OPTIONS $OPENSSL_OPTIONS *****"

cd "$OPENSSL_SRC"

for BUILDARCH in $BUILDARCHS
do
    echo "***** BUILDING UNIVERSAL ARCH $BUILDARCH ******"
    make clean

    # disable assembler
    echo "***** configuring WITHOUT assembler optimizations based on architecture $BUILDARCH and build style $BUILD_STYLE *****"
    ./config no-asm $OPENSSL_OPTIONS --openssldir="$OPENSSLDIR" --prefix="$OPENSSLDIR"
    ASM_DEF="-UOPENSSL_BN_ASM_PART_WORDS"

    make CFLAG="-D_DARWIN_C_SOURCE $ASM_DEF -arch $BUILDARCH $ISYSROOT -Wno-unused-value -Wno-parentheses" SHARED_LDFLAGS="-arch $BUILDARCH -dynamiclib"
    make -j install
    
    echo "***** copying intermediate libraries to $CONFIGURATION_TEMP_DIR/$BUILDARCH-*.a *****"
    cp "$OPENSSLDIR/lib/libcrypto.a" "$CONFIGURATION_TEMP_DIR"/$BUILDARCH-libcrypto.a
    cp "$OPENSSLDIR/lib/libssl.a" "$CONFIGURATION_TEMP_DIR"/$BUILDARCH-libssl.a
done

echo "***** creating universallibraries in $TARGET_BUILD_DIR *****"
mkdir -p "$TARGET_BUILD_DIR"
lipo -create "$CONFIGURATION_TEMP_DIR/"*-libcrypto.a -output "$TARGET_BUILD_DIR/libcrypto.a"
lipo -create "$CONFIGURATION_TEMP_DIR/"*-libssl.a -output "$TARGET_BUILD_DIR/libssl.a"

echo "***** removing temporary files from $CONFIGURATION_TEMP_DIR *****"
rm -f "$CONFIGURATION_TEMP_DIR/"*-libcrypto.a
rm -f "$CONFIGURATION_TEMP_DIR/"*-libssl.a

echo "***** executing ranlib on libraries in $TARGET_BUILD_DIR *****"
ranlib "$TARGET_BUILD_DIR/libcrypto.a"
ranlib "$TARGET_BUILD_DIR/libssl.a"

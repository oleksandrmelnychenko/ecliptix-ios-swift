#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -d "$PROJECT_ROOT/Ecliptix-iOS/Protos" ]; then
    APP_ROOT="$PROJECT_ROOT/Ecliptix-iOS"
elif [ -d "$PROJECT_ROOT/Protos" ]; then
    APP_ROOT="$PROJECT_ROOT"
else
    echo "error: could not locate Protos directory from $PROJECT_ROOT" >&2
    exit 1
fi

PROTOS_DIR="$APP_ROOT/Protos"
GENERATED_DIR="$APP_ROOT/Generated/Protos"
BUILD_DIR="$APP_ROOT/.build"
STAMP_PATH="${PROTO_STAMP_PATH:-$BUILD_DIR/proto-generation.stamp}"
FINGERPRINT_PATH="$BUILD_DIR/proto-generation.sha256"

mkdir -p "$BUILD_DIR"

PROTOC_BIN="$(command -v protoc || true)"
PROTOC_GEN_SWIFT_BIN="$(command -v protoc-gen-swift || true)"
PROTOC_GEN_GRPC_SWIFT_BIN="$(command -v protoc-gen-grpc-swift || true)"

if [ -z "$PROTOC_BIN" ] || [ -z "$PROTOC_GEN_SWIFT_BIN" ] || [ -z "$PROTOC_GEN_GRPC_SWIFT_BIN" ]; then
    echo "error: required tools are missing (protoc, protoc-gen-swift, protoc-gen-grpc-swift)" >&2
    exit 1
fi

PROTO_FILES=()
while IFS= read -r proto; do
    PROTO_FILES+=("$proto")
done < <(find "$PROTOS_DIR" -type f -name "*.proto" | LC_ALL=C sort)

if [ "${#PROTO_FILES[@]}" -eq 0 ]; then
    echo "error: no .proto files found under $PROTOS_DIR" >&2
    exit 1
fi

all_outputs_present() {
    local output_root="$1"
    local proto rel base
    for proto in "${PROTO_FILES[@]}"; do
        rel="${proto#"$PROTOS_DIR"/}"
        base="${rel%.proto}"
        if [ ! -f "$output_root/$base.pb.swift" ] || [ ! -f "$output_root/$base.grpc.swift" ]; then
            return 1
        fi
    done
    return 0
}

compute_fingerprint() {
    {
        echo "$("$PROTOC_BIN" --version)"
        echo "swift_plugin=$PROTOC_GEN_SWIFT_BIN"
        echo "grpc_plugin=$PROTOC_GEN_GRPC_SWIFT_BIN"
        "$PROTOC_GEN_SWIFT_BIN" --version 2>/dev/null || true
        "$PROTOC_GEN_GRPC_SWIFT_BIN" --version 2>/dev/null || true
        local proto
        for proto in "${PROTO_FILES[@]}"; do
            shasum -a 256 "$proto"
        done
    } | shasum -a 256 | awk '{print $1}'
}

CURRENT_FINGERPRINT="$(compute_fingerprint)"
PREVIOUS_FINGERPRINT=""
if [ -f "$FINGERPRINT_PATH" ]; then
    PREVIOUS_FINGERPRINT="$(cat "$FINGERPRINT_PATH")"
fi

if [ "$CURRENT_FINGERPRINT" = "$PREVIOUS_FINGERPRINT" ] && all_outputs_present "$GENERATED_DIR"; then
    echo "proto generation: up to date ($GENERATED_DIR)"
    mkdir -p "$(dirname "$STAMP_PATH")"
    touch "$STAMP_PATH"
    exit 0
fi

echo "proto generation: regenerating ${#PROTO_FILES[@]} files into $GENERATED_DIR"
TMP_OUTPUT_DIR="$(mktemp -d "$BUILD_DIR/proto-generation.XXXXXX")"
cleanup_tmp() {
    rm -rf "$TMP_OUTPUT_DIR"
}
trap cleanup_tmp EXIT

"$PROTOC_BIN" \
    --proto_path="$PROTOS_DIR" \
    --swift_out="$TMP_OUTPUT_DIR" \
    --swift_opt=Visibility=Public \
    --grpc-swift_out="$TMP_OUTPUT_DIR" \
    --grpc-swift_opt=Visibility=Public \
    "${PROTO_FILES[@]}"

if ! all_outputs_present "$TMP_OUTPUT_DIR"; then
    echo "error: generation completed but expected output files are missing in $TMP_OUTPUT_DIR" >&2
    exit 1
fi

mkdir -p "$GENERATED_DIR"

find "$GENERATED_DIR" -type f \( -name "* 2.swift" -o -name "* copy*.swift" \) -delete 2>/dev/null || true

while IFS= read -r src; do
    rel="${src#"$TMP_OUTPUT_DIR"/}"
    case "$rel" in
        *" 2.swift"|*" copy"*.swift) continue ;;
    esac
    dst="$GENERATED_DIR/$rel"
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        cp "$src" "$dst"
    fi
done < <(find "$TMP_OUTPUT_DIR" -type f -name "*.swift" | LC_ALL=C sort)

if [ "${PROTO_REMOVE_STALE:-0}" = "1" ]; then
    while IFS= read -r existing; do
        rel="${existing#"$GENERATED_DIR"/}"
        if [ ! -f "$TMP_OUTPUT_DIR/$rel" ]; then
            rm -f "$existing"
        fi
    done < <(find "$GENERATED_DIR" -type f -name "*.swift" | LC_ALL=C sort)
fi

echo "$CURRENT_FINGERPRINT" > "$FINGERPRINT_PATH"
mkdir -p "$(dirname "$STAMP_PATH")"
touch "$STAMP_PATH"

GENERATED_COUNT="$(find "$GENERATED_DIR" -type f -name "*.swift" | wc -l | tr -d ' ')"
echo "proto generation: wrote $GENERATED_COUNT swift files"

#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


IGNORED_CLIENT_ONLY_FILES = {
    "common/application_settings.proto",
    "common/encryption.proto",
    "common/types.proto",
    "transport/device_provisioning.proto",
}


@dataclass(frozen=True)
class FieldSig:
    number: int
    name: str
    label: str
    field_type: str
    type_name: str | None
    proto3_optional: bool
    oneof_name: str | None


@dataclass(frozen=True)
class MessageSig:
    symbol: str
    file_name: str
    fields: tuple[FieldSig, ...]


@dataclass(frozen=True)
class EnumSig:
    symbol: str
    file_name: str
    values: tuple[tuple[int, str], ...]


@dataclass(frozen=True)
class MethodSig:
    name: str
    input_type: str
    output_type: str
    client_streaming: bool
    server_streaming: bool


@dataclass(frozen=True)
class ServiceSig:
    symbol: str
    file_name: str
    methods: tuple[MethodSig, ...]


@dataclass(frozen=True)
class DescriptorIndex:
    messages: dict[str, MessageSig]
    enums: dict[str, EnumSig]
    services: dict[str, ServiceSig]
    file_count: int


def main() -> int:
    args = parse_args()

    client_root = resolve_client_root(args.client_root)
    server_root = resolve_server_root(args.server_root, client_root)

    ensure_tool("buf")

    client_index = load_index(client_root)
    server_index = load_index(server_root)

    report = build_report(client_index, server_index)

    print(f"client proto root: {client_root}")
    print(f"server proto root: {server_root}")
    print(
        "loaded "
        f"{client_index.file_count} client files, "
        f"{server_index.file_count} server files"
    )
    print(
        "indexed "
        f"{len(client_index.messages)} client / {len(server_index.messages)} server messages, "
        f"{len(client_index.enums)} client / {len(server_index.enums)} server enums, "
        f"{len(client_index.services)} client / {len(server_index.services)} server services"
    )

    if not report:
        print("proto contract is in sync")
        return 0

    print(f"proto contract drift detected: {len(report)} issue(s)")
    for line in report[: args.max_diffs]:
        print(line)

    if len(report) > args.max_diffs:
        remaining = len(report) - args.max_diffs
        print(f"... truncated {remaining} additional issue(s)")

    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare iOS and server protobuf contracts by symbol and wire shape, "
            "ignoring comments, file paths, swift_prefix, and formatting."
        )
    )
    parser.add_argument(
        "--client-root",
        type=Path,
        help="Path to the iOS proto root. Defaults to the local Protos directory.",
    )
    parser.add_argument(
        "--server-root",
        type=Path,
        help=(
            "Path to the server proto root. Defaults to ECLIPTIX_SERVER_PROTO_ROOT "
            "or a nearby ecliptix-auth-relay checkout."
        ),
    )
    parser.add_argument(
        "--max-diffs",
        type=int,
        default=200,
        help="Maximum number of drift lines to print before truncation.",
    )
    return parser.parse_args()


def ensure_tool(tool_name: str) -> None:
    try:
        subprocess.run(
            [tool_name, "--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError as exc:
        raise SystemExit(
            f"error: required tool '{tool_name}' is not installed. "
            "Run ./Scripts/setup-proto-tools.sh first."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"error: failed to execute '{tool_name} --version': {exc}") from exc


def resolve_client_root(explicit_root: Path | None) -> Path:
    if explicit_root is not None:
        return require_proto_root(explicit_root)

    script_dir = Path(__file__).resolve().parent
    project_root = script_dir.parent
    candidates = (
        project_root / "Ecliptix-iOS" / "Protos",
        project_root / "Protos",
    )
    for candidate in candidates:
        if candidate.is_dir():
            return candidate.resolve()
    raise SystemExit(
        "error: could not locate the iOS Protos directory. "
        "Pass --client-root explicitly."
    )


def resolve_server_root(explicit_root: Path | None, client_root: Path) -> Path:
    if explicit_root is not None:
        return require_proto_root(explicit_root)

    env_value = os.environ.get("ECLIPTIX_SERVER_PROTO_ROOT")
    if env_value:
        env_root = Path(env_value)
        return require_proto_root(env_root)

    anchors = (
        client_root.parent,
        client_root.parent.parent,
        Path.cwd(),
    )
    relative_candidates = (
        "Ecliptix.Protobufs/Protobuf",
        "../ecliptix-auth-relay/Ecliptix.Protobufs/Protobuf",
        "../../ecliptix-auth-relay/Ecliptix.Protobufs/Protobuf",
        "../../../ecliptix-auth-relay/Ecliptix.Protobufs/Protobuf",
        "../../../../ecliptix-auth-relay/Ecliptix.Protobufs/Protobuf",
    )
    candidates = tuple(anchor / relative for anchor in anchors for relative in relative_candidates)
    for candidate in candidates:
        if candidate.is_dir():
            return candidate.resolve()
    raise SystemExit(
        "error: could not locate the server proto root. "
        "Pass --server-root or set ECLIPTIX_SERVER_PROTO_ROOT."
    )


def require_proto_root(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.is_dir():
        raise SystemExit(f"error: proto root does not exist: {resolved}")
    if not any(resolved.rglob("*.proto")):
        raise SystemExit(f"error: no .proto files found under: {resolved}")
    return resolved


def load_index(proto_root: Path) -> DescriptorIndex:
    image = build_descriptor_image(proto_root)

    messages: dict[str, MessageSig] = {}
    enums: dict[str, EnumSig] = {}
    services: dict[str, ServiceSig] = {}

    for file_descriptor in image.get("file", []):
        package = file_descriptor.get("package", "")
        file_name = file_descriptor.get("name", "<unknown>")
        if package.startswith("google.protobuf"):
            continue

        for enum_descriptor in file_descriptor.get("enumType", []):
            collect_enum(enums, package, (), file_name, enum_descriptor)

        for message_descriptor in file_descriptor.get("messageType", []):
            collect_message(messages, enums, package, (), file_name, message_descriptor)

        for service_descriptor in file_descriptor.get("service", []):
            collect_service(services, package, file_name, service_descriptor)

    return DescriptorIndex(
        messages=messages,
        enums=enums,
        services=services,
        file_count=len(image.get("file", [])),
    )


def build_descriptor_image(proto_root: Path) -> dict[str, Any]:
    with tempfile.NamedTemporaryFile(suffix=".json") as tmp_file:
        try:
            subprocess.run(
                [
                    "buf",
                    "build",
                    ".",
                    "--as-file-descriptor-set",
                    "--exclude-source-info",
                    "--exclude-source-retention-options",
                    "-o",
                    tmp_file.name,
                ],
                check=True,
                capture_output=True,
                text=True,
                cwd=proto_root,
            )
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.strip()
            raise SystemExit(
                "error: buf build failed for "
                f"{proto_root}\n{stderr}"
            ) from exc

        with Path(tmp_file.name).open("r", encoding="utf-8") as handle:
            return json.load(handle)


def collect_message(
    messages: dict[str, MessageSig],
    enums: dict[str, EnumSig],
    package: str,
    parents: tuple[str, ...],
    file_name: str,
    descriptor: dict[str, Any],
) -> None:
    options = descriptor.get("options", {})
    if options.get("mapEntry", False):
        return

    symbol = fully_qualified_name(package, parents + (descriptor["name"],))
    oneof_names = [entry["name"] for entry in descriptor.get("oneofDecl", [])]
    fields = []
    for field in descriptor.get("field", []):
        oneof_index = field.get("oneofIndex")
        oneof_name = None
        if oneof_index is not None and 0 <= oneof_index < len(oneof_names):
            oneof_name = oneof_names[oneof_index]
        fields.append(
            FieldSig(
                number=field["number"],
                name=field["name"],
                label=field["label"],
                field_type=field["type"],
                type_name=normalize_type_name(field.get("typeName")),
                proto3_optional=field.get("proto3Optional", False),
                oneof_name=oneof_name,
            )
        )

    messages[symbol] = MessageSig(
        symbol=symbol,
        file_name=file_name,
        fields=tuple(sorted(fields, key=lambda field: field.number)),
    )

    child_parents = parents + (descriptor["name"],)
    for enum_descriptor in descriptor.get("enumType", []):
        collect_enum(enums, package, child_parents, file_name, enum_descriptor)
    for message_descriptor in descriptor.get("nestedType", []):
        collect_message(messages, enums, package, child_parents, file_name, message_descriptor)


def collect_enum(
    enums: dict[str, EnumSig],
    package: str,
    parents: tuple[str, ...],
    file_name: str,
    descriptor: dict[str, Any],
) -> None:
    symbol = fully_qualified_name(package, parents + (descriptor["name"],))
    values = tuple(
        sorted(
            ((value["number"], value["name"]) for value in descriptor.get("value", [])),
            key=lambda item: (item[0], item[1]),
        )
    )
    enums[symbol] = EnumSig(symbol=symbol, file_name=file_name, values=values)


def collect_service(
    services: dict[str, ServiceSig],
    package: str,
    file_name: str,
    descriptor: dict[str, Any],
) -> None:
    symbol = fully_qualified_name(package, (descriptor["name"],))
    methods = []
    for method in descriptor.get("method", []):
        methods.append(
            MethodSig(
                name=method["name"],
                input_type=normalize_type_name(method["inputType"]),
                output_type=normalize_type_name(method["outputType"]),
                client_streaming=method.get("clientStreaming", False),
                server_streaming=method.get("serverStreaming", False),
            )
        )

    services[symbol] = ServiceSig(
        symbol=symbol,
        file_name=file_name,
        methods=tuple(sorted(methods, key=lambda method: method.name)),
    )


def fully_qualified_name(package: str, parts: tuple[str, ...]) -> str:
    filtered_parts = tuple(part for part in parts if part)
    if package:
        return ".".join((package, *filtered_parts))
    return ".".join(filtered_parts)


def normalize_type_name(type_name: str | None) -> str | None:
    if type_name is None:
        return None
    return type_name.lstrip(".")


def build_report(client_index: DescriptorIndex, server_index: DescriptorIndex) -> list[str]:
    report: list[str] = []
    report.extend(compare_symbol_maps("message", client_index.messages, server_index.messages, compare_message))
    report.extend(compare_symbol_maps("enum", client_index.enums, server_index.enums, compare_enum))
    report.extend(compare_symbol_maps("service", client_index.services, server_index.services, compare_service))
    return report


def compare_symbol_maps(
    kind: str,
    client_map: dict[str, Any],
    server_map: dict[str, Any],
    comparer,
) -> list[str]:
    lines: list[str] = []
    client_keys = set(client_map)
    server_keys = set(server_map)

    for symbol in sorted(client_keys - server_keys):
        client_sig = client_map[symbol]
        if client_sig.file_name in IGNORED_CLIENT_ONLY_FILES:
            continue
        lines.append(f"- client-only {kind} {symbol} ({client_sig.file_name})")

    for symbol in sorted(server_keys - client_keys):
        lines.append(f"- server-only {kind} {symbol} ({server_map[symbol].file_name})")

    for symbol in sorted(client_keys & server_keys):
        lines.extend(comparer(client_map[symbol], server_map[symbol]))

    return lines


def compare_message(client_sig: MessageSig, server_sig: MessageSig) -> list[str]:
    lines: list[str] = []
    client_fields = {field.number: field for field in client_sig.fields}
    server_fields = {field.number: field for field in server_sig.fields}

    for number in sorted(client_fields.keys() - server_fields.keys()):
        field = client_fields[number]
        lines.append(
            "- message mismatch "
            f"{client_sig.symbol}: client-only field #{number} "
            f"{field.name} [{format_field(field)}]"
        )

    for number in sorted(server_fields.keys() - client_fields.keys()):
        field = server_fields[number]
        lines.append(
            "- message mismatch "
            f"{client_sig.symbol}: server-only field #{number} "
            f"{field.name} [{format_field(field)}]"
        )

    for number in sorted(client_fields.keys() & server_fields.keys()):
        client_field = client_fields[number]
        server_field = server_fields[number]
        if client_field == server_field:
            continue
        lines.append(
            "- message mismatch "
            f"{client_sig.symbol}: field #{number} "
            f"client[{format_field(client_field)}] "
            f"server[{format_field(server_field)}]"
        )

    return lines


def compare_enum(client_sig: EnumSig, server_sig: EnumSig) -> list[str]:
    if client_sig.values == server_sig.values:
        return []
    return [
        "- enum mismatch "
        f"{client_sig.symbol}: client{format_enum_values(client_sig.values)} "
        f"server{format_enum_values(server_sig.values)}"
    ]


def compare_service(client_sig: ServiceSig, server_sig: ServiceSig) -> list[str]:
    lines: list[str] = []
    client_methods = {method.name: method for method in client_sig.methods}
    server_methods = {method.name: method for method in server_sig.methods}

    for method_name in sorted(client_methods.keys() - server_methods.keys()):
        lines.append(
            "- service mismatch "
            f"{client_sig.symbol}: client-only rpc {method_name} "
            f"[{format_method(client_methods[method_name])}]"
        )

    for method_name in sorted(server_methods.keys() - client_methods.keys()):
        lines.append(
            "- service mismatch "
            f"{client_sig.symbol}: server-only rpc {method_name} "
            f"[{format_method(server_methods[method_name])}]"
        )

    for method_name in sorted(client_methods.keys() & server_methods.keys()):
        client_method = client_methods[method_name]
        server_method = server_methods[method_name]
        if client_method == server_method:
            continue
        lines.append(
            "- service mismatch "
            f"{client_sig.symbol}: rpc {method_name} "
            f"client[{format_method(client_method)}] "
            f"server[{format_method(server_method)}]"
        )

    return lines


def format_field(field: FieldSig) -> str:
    parts = [field.name, field.label, field.field_type]
    if field.type_name is not None:
        parts.append(field.type_name)
    if field.proto3_optional:
        parts.append("proto3_optional")
    if field.oneof_name is not None:
        parts.append(f"oneof={field.oneof_name}")
    return ", ".join(parts)


def format_enum_values(values: tuple[tuple[int, str], ...]) -> str:
    formatted = ", ".join(f"{number}:{name}" for number, name in values)
    return "[" + formatted + "]"


def format_method(method: MethodSig) -> str:
    mode = []
    if method.client_streaming:
        mode.append("client_stream")
    if method.server_streaming:
        mode.append("server_stream")
    streaming = ",".join(mode) if mode else "unary"
    return f"{method.input_type} -> {method.output_type}, {streaming}"


if __name__ == "__main__":
    sys.exit(main())

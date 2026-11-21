#!/usr/bin/env python3
"""Regenerate lib/features/sources/clicli/protocol/esdk_tables.dart.

Usage:
  python tool/clicli/gen_tables.py "D:/project-Auto/CliCli动漫/dm-client/_consts.json"
"""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "lib", "features", "sources", "clicli", "protocol", "esdk_tables.dart")


def emit(lines, name, values, per=12):
    lines.append("const List<int> %s = <int>[" % name)
    for i in range(0, len(values), per):
        lines.append("  " + ", ".join(str(v) for v in values[i:i + per]) + ",")
    lines.append("];")
    lines.append("")


def main(argv):
    src = argv[1] if len(argv) > 1 else "_consts.json"
    c = json.load(open(src, encoding="utf-8"))
    lines = [
        "// Generated from CliCli 1.0.10 libmagic_cipher.so static tables.",
        "// Do not edit by hand; run tool/clicli/gen_tables.py to regenerate.",
        "",
    ]
    emit(lines, "kRc4S0", c["rc4_S0"])
    emit(lines, "kBfP", c["bf_P"])
    emit(lines, "kBfS", c["bf_S"])

    alpha = c["b64_alpha"].split("\x00")[0]
    assert len(alpha) == 64, len(alpha)
    lines.append("const String kB64Alpha = '%s';" % alpha)
    lines.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT, "rc4", len(c["rc4_S0"]), "bfS", len(c["bf_S"]), "b64", len(alpha))


if __name__ == "__main__":
    main(sys.argv)

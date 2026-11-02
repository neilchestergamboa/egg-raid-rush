"""Canonicalize Zap's generated result-code type declaration order."""

from pathlib import Path
import re
import sys


TYPE_PATTERN = re.compile(rb"export type (Carry|Egg|Fight)ActionResultCode =")
EXPECTED_TYPES = {b"Carry", b"Egg", b"Fight"}


def normalize(path: Path) -> None:
    lines = path.read_bytes().splitlines(keepends=True)
    positions: list[int] = []
    definitions: dict[bytes, bytes] = {}

    for index, line in enumerate(lines):
        match = TYPE_PATTERN.match(line)
        if match is not None:
            name = match.group(1)
            if name in definitions:
                raise ValueError(f"duplicate {name.decode()} result type in {path}")
            positions.append(index)
            definitions[name] = line

    if set(definitions) != EXPECTED_TYPES:
        found = ", ".join(sorted(name.decode() for name in definitions)) or "none"
        raise ValueError(f"expected Carry, Egg, and Fight result types in {path}; found {found}")

    for index, name in zip(positions, sorted(definitions)):
        lines[index] = definitions[name]

    path.write_bytes(b"".join(lines))


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: normalize-zap-types.py <generated-file> [<generated-file> ...]", file=sys.stderr)
        return 2

    try:
        for filename in sys.argv[1:]:
            normalize(Path(filename))
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

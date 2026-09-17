"""Format project Verilog sources with MiSTer's tab indentation."""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {".v", ".sv", ".vh", ".svh"}
SOURCES = [
    "Apple-III.sv",
    "rtl",
    "sim",
    ":(exclude)sys/**",
    ":(exclude)rtl/acia/**",
    ":(exclude)rtl/disk/woz/**",
    ":(exclude)rtl/pll.v",
    ":(exclude)rtl/pll/**",
    ":(exclude)sim/gen/**",
    ":(exclude)sim/obj_dir/**",
    ":(exclude)sim/work/**",
]

# Match protected text before indentation, so tabs never alter strings, block
# comment contents, escaped identifiers, or explicitly disabled format regions.
INDENT = re.compile(
    rb"//[^\n]*verilog_format:\s*off\b[\s\S]*?(?=//[^\n]*verilog_format:\s*on\b|\Z)"
    rb'|"(?:\\[\s\S]|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*|\\\S+'
    rb"|(?P<indent>^[ \t]+)",
    re.MULTILINE,
)


def indentation(text, tabs):
    def replace(match):
        prefix = match.group("indent")
        if prefix is None:
            return match.group()
        width = len(prefix.expandtabs(4))
        return b"\t" * (width // 4) + b" " * (width % 4) if tabs else b" " * width

    return INDENT.sub(replace, text)


def format_source(path, source):
    result = subprocess.run(
        [
            "verible-verilog-format",
            f"--flagfile={ROOT / '.verible-format.flags'}",
            f"--stdin_name={path}",
            "-",
        ],
        input=indentation(source, tabs=False),
        stdout=subprocess.PIPE,
        check=True,
    )
    return indentation(result.stdout, tabs=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("format", "format-check"))
    parser.add_argument(
        "files", nargs="*", help="optional project source paths (default: all)"
    )
    args = parser.parse_args()

    # Include new, untracked sources, but never ignored build/research artifacts.
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            *SOURCES,
        ],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        check=True,
    )
    files = sorted(
        {
            Path(name.decode())
            for name in result.stdout.split(b"\0")
            if name
            and Path(name.decode()).suffix in EXTENSIONS
            and (ROOT / name.decode()).is_file()
        }
    )
    if args.files:
        selected = []
        for name in args.files:
            path = Path(name).resolve()
            if not path.is_relative_to(ROOT) or path.relative_to(ROOT) not in files:
                parser.error(
                    f"file excluded from {args.command} or not an existing Verilog source: {name}"
                )
            selected.append(path.relative_to(ROOT))
        files = sorted(set(selected))
    if not files:
        parser.error("no project Verilog sources found")

    print(f"{args.command}: {len(files)} project Verilog files", flush=True)
    failed = False
    for path in files:
        original = (ROOT / path).read_bytes()
        try:
            formatted = format_source(path, original)
        except subprocess.CalledProcessError:
            print(f"Failed to format: {path}", file=sys.stderr)
            failed = True
            continue
        if formatted != original:
            if args.command == "format-check":
                print(f"Would reformat: {path}")
                failed = True
            else:
                (ROOT / path).write_bytes(formatted)
                print(f"Formatted: {path}")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"verible: {error}", file=sys.stderr)
        sys.exit(1)

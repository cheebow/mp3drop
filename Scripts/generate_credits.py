#!/usr/bin/env python3
"""Generates MP3Drop/Resources/Credits.rtf, shown in the standard About panel.

The LGPL requires every distributed copy of the app to carry a notice that it
uses LAME and a copy of the license, so the full LGPL text is taken from the
vendored LAME tarball (COPYING) and embedded here. See THIRD_PARTY_LICENSES.md.
"""

import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARBALL = ROOT / "Vendor" / "lame-3.100.tar.gz"
OUT = ROOT / "MP3Drop" / "Resources" / "Credits.rtf"

NOTICE = [
    "MP3 encoding is powered by LAME (libmp3lame) 3.100.\nhttps://lame.sourceforge.io",
    "LAME is free software licensed under the GNU Lesser General Public "
    "License version 2 or later. It is dynamically linked "
    "(Contents/Frameworks/libmp3lame.dylib), so you can replace it with your "
    "own build. After replacing it, re-sign the app ad hoc with: "
    "codesign --force --deep -s - MP3Drop.app",
    "The complete source code of LAME used in this app, together with the "
    "build script, is available at:\nhttps://github.com/cheebow/mp3drop "
    "(Vendor/lame-3.100.tar.gz, Scripts/build_lame.sh)",
    "LAME is distributed in the hope that it will be useful, but WITHOUT ANY "
    "WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS "
    "FOR A PARTICULAR PURPOSE. See the license below for more details.",
]


def escape(text: str) -> str:
    text = text.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}")
    return text.replace("\n", "\\\n")


def reflow(license_text: str) -> list[str]:
    """Joins hard-wrapped lines so the text wraps to the About panel width."""
    paragraphs = []
    for block in license_text.split("\n\n"):
        lines = [line.strip() for line in block.strip("\n").splitlines()]
        if any(lines):
            paragraphs.append(" ".join(line for line in lines if line))
    return paragraphs


def paragraph(text: str, bold: bool = False) -> str:
    body = escape(text)
    if bold:
        body = "\\b " + body + "\\b0 "
    return body + "\\\n\\\n"


def main() -> None:
    with tarfile.open(TARBALL) as tar:
        member = tar.extractfile("lame-3.100/COPYING")
        license_text = member.read().decode("ascii")

    parts = [
        "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2870\n",
        "{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;}\n",
        # \cf0 (no explicit color) keeps the text readable in Dark Mode.
        "\\pard\\pardirnatural\\partightenfactor0\n\\f0\\fs20 \\cf0 ",
        paragraph("LAME", bold=True),
    ]
    parts += [paragraph(p) for p in NOTICE]
    parts.append(paragraph("GNU Library General Public License, Version 2", bold=True))
    parts.append("\\fs18 ")
    parts += [paragraph(p) for p in reflow(license_text)]
    parts.append("}\n")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("".join(parts), encoding="ascii")
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

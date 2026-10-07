# Third-Party Licenses

## LAME (libmp3lame) 3.100

MP3 Drop uses the LAME MP3 encoding library.

- Website: https://lame.sourceforge.io
- Version: 3.100
- License: GNU Lesser General Public License v2 (LGPL-2.0-or-later)

LAME is linked **dynamically** (`libmp3lame.dylib` embedded in the app
bundle), so users can replace the library with their own build, as the LGPL
requires. The complete, unmodified source code used to build the library is
included in this repository at `Vendor/lame-3.100.tar.gz` and can be rebuilt
with `Scripts/build_lame.sh`.

The only modification applied at build time is the removal of the
`lame_init_old` entry from `include/libmp3lame.sym` (the symbol is not
emitted by modern compilers and otherwise breaks the link). See
`Scripts/build_lame.sh` for the exact patch.

LAME is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for
more details: https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html

> Note for Mac App Store distribution: review Apple's and the LGPL's terms
> before submission. Dynamic linking plus the included source satisfies the
> relink requirement, but the final legal check is part of the release
> process.

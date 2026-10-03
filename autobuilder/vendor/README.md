# Bundled dependency

`libdeflate.lua`: [LibDeflate](https://github.com/SafeteeWoW/LibDeflate),
commit `afc3b78d12fb3bcfa6b21e5332031ad3d7572e19`, zlib license
(copyright/license preserved in the source). No runtime download/dependencies.

AutoBuilder changes are marked in the source: `DecompressDeflateBounded` adds a
maximum expanded size and progress callback, checked at both32KiB output flushes
and after every block before final concatenation. Existing methods are unchanged.
The decoder may transiently assemble at most one DEFLATE stored block or its
64KiB working buffer beyond the requested bound; it rejects before retaining or
returning that excess. Our gzip wrapper supplies the bound and cooperative yield.

Keep the pinned implementation intact when upgrading, reapply these small hooks,
and run `tests/native_gzip_test.lua` including stored/fixed/dynamic and corrupt
streams. Upstream implements DEFLATE/zlib; our wrapper validates gzip headers,
CRC32, ISIZE and exact end-of-member boundaries.

Unmodified pinned source SHA-256:
`880e396fbaac7dcf99d33fc706a7f129147f2910f8414a143f8dea57e327c06b`.

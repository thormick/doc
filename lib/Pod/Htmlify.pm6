unit module Pod::Htmlify;

use URI::Escape;

#| Return the SVG for the given file, without its XML header
sub svg-for-file($file) is export {
    join "\n", grep { /^'<svg'/ ff False }, $file.IO.lines;
}

# vim: expandtab shiftwidth=4 ft=perl6

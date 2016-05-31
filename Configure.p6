use v6.c;

sub MAIN {
    my $inputfile = "tools/build/Makefile.in";
    my @output;
    for $inputfile.IO.lines -> $line {
        @output.push($line);
    }
    spurt "Makefile", @output.join("\n");
}

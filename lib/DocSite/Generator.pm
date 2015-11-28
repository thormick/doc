unit class DocSite::Generator;

use lib 'lib';

use DocSite::Document::Registry;
use DocSite::Pod::To::HTML;
use DocSite::TypeGraph::Viz;
use DocSite::TypeGraph;
use Pod::Convenience;
use Pod::Htmlify;
use Term::ProgressBar;
use URI::Escape;

has Bool $!overwrite-typegraph;
has Bool $!disambiguation;
has Bool $!search-file;
has Bool $!highlight;
has Bool $!inline-python;
has Bool $!verbose;
has Int  $!sparse;
has Int  $!threads;
has IO::Path $!root;

has DocSite::Document::Registry $!registry = DocSite::Document::Registry.new;
has DocSite::TypeGraph $!type-graph;

my @viz-formats = (
    %( :format<svg> ),
    %( :format<png>, :size<8,3> ),
);

method BUILD (
    Bool :$!overwrite-typegraph,
    Bool :$!disambiguation,
    Bool :$!search-file,
    Bool :$!highlight,
    Bool :$!inline-python,
    Bool :$!verbose,
    Int  :$!sparse,
    Int  :$!threads,
    IO::Path :$!root,
) { }

method run {
    self!maybe-write-type-graph-images;
    self!process-language-pod;
    self!process-type-pod;
}

method !maybe-write-type-graph-images {
    my $image-dir = IO::Path.new( $*SPEC.catdir( $!root, 'html', 'images' ) );
    my $any-svg = $*SPEC.catfile( $image-dir, 'type-graph-Any.svg' ).IO;
    if $any-svg ~~ :e && !$!overwrite-typegraph {
        self!maybe-say( qq:to/END/ );
        Not writing type graph images, it seems to be up-to-date. To forcibly
        overwrite the type graph images, supply the --overwrite-typegraph
        option at the command line, or delete the file
        $any-svg
        END
        return;
    }

    my $tg-file = 'type-graph.txt';
    self!maybe-say: "Reading type graph from $tg-file ...";
    $!type-graph = DocSite::TypeGraph.new-from-file($tg-file);
    self!write-type-graph-images($image-dir);
    self!write-specialized-type-graph-images($image-dir);
}

method !write-type-graph-images (IO::Path $image-dir) {
    self!maybe-say: "Writing type graph images to $image-dir {$!threads > 1 ?? qq{with $!threads threads } !! q{}}...";
    self!run-with-progress(
        $!type-graph.sorted.cache,
        sub ($type) { self!write-one-type( $type, $image-dir ) },
    );
}

method !write-one-type (DocSite::Type $type, IO::Path $image-dir) {
    my $viz = DocSite::TypeGraph::Viz.new-for-type($type);
    for @viz-formats -> $args {
        my $file = $*SPEC.catfile( $image-dir, "type-graph-{$type}.{$args<format>}" );
        $viz.to-file( $file, |$args );
    }
}

method !write-specialized-type-graph-images (IO::Path $image-dir) {
    self!maybe-say: "Writing specialized visualizations to $image-dir ...";
    my %by-group = $!type-graph.sorted.classify(&viz-group);
    %by-group<Exception>.append: $!type-graph.types< Exception Any Mu >;
    %by-group<Metamodel>.append: $!type-graph.types< Any Mu >;

    self!run-with-progress(
        %by-group.pairs.cache,
        sub (Pair $pair) { self!write-one-type-group( $pair.key, $pair.value, $image-dir ) },
    );
}

method !write-one-type-group (Str $group, Array $types, IO::Path $image-dir) {
    my $viz = DocSite::TypeGraph::Viz.new(
        :types($types),
        :dot-hints( viz-hints($group) ),
        :rank-dir<LR>,
    );
    for @viz-formats -> $args {
        my $file = $*SPEC.catfile( $image-dir, "type-graph-{$group}.{$args<format>}" );
        $viz.to-file($file, |$args);
    }
}

sub viz-group ($type) {
    return 'Metamodel' if $type.name ~~ /^ 'Perl6::Metamodel' /;
    return 'Exception' if $type.name ~~ /^ 'X::' /;
    return 'Any';
}

sub viz-hints ($group) {
    return q{} unless $group eq 'Any';

    return Q:to/END/;
    subgraph "cluster: Mu children" {
        rank=same;
        style=invis;
        "Any";
        "Junction";
    }
    subgraph "cluster: Pod:: top level" {
        rank=same;
        style=invis;
        "Pod::Config";
        "Pod::Block";
    }
    subgraph "cluster: Date/time handling" {
        rank=same;
        style=invis;
        "Date";
        "DateTime";
        "DateTime-local-timezone";
    }
    subgraph "cluster: Collection roles" {
        rank=same;
        style=invis;
        "Positional";
        "Associative";
        "Baggy";
    }
    END
}

method !process-language-pod {
    my $kind = 'Language';
    my @files = self!find-pod-files-in($kind);
    if $!sparse {
         @files = @files[^(@files / $!sparse).ceiling];
    }

    self!maybe-say("Reading and process $kind pod files ...");
    self!run-with-progress(
        @files,
        sub ($file) {
            self!process-one-pod( $file, $kind );
        }
    )
}

method !process-type-pod {
}

method !find-pod-files-in (Str $dir) {
    self!maybe-say: "Finding pod sources in $dir ...";
    return gather {
        for self!recursive-files-in($dir) -> $file {
            take $file if $file.path ~~ / '.pod' $/;
        }
    }
}

method !recursive-files-in($dir) {
    my @todo = $*SPEC.catdir( $!root, 'doc', $dir );
    return gather {
        while @todo {
            my $d = @todo.shift;
            for dir($d) -> $f {
                if $f.f {
                    self!maybe-say: " ... found $f";
                    take $f;
                }
                else {
                    self!maybe-say: " ... descending into $f";
                    @todo.append( $f.path );
                }
            }
        }
    }
}

method !process-one-pod (IO::Path $file, Str $kind) {
    my $pod = EVAL( $file.slurp ~ "\n\$=pod[0]" );
    my $pth = DocSite::Pod::To::HTML.new;
    my $html = $pth.pod-to-html($pod);

    self!spurt-html-file( $file, $kind, $html);
}

method !spurt-html-file (IO::Path $file, Str $kind, Str $html) {
    my $dir = IO::Path.new( $*SPEC.catfile( $!root, 'html', $kind.lc ) );
    unless $dir ~~ :e {
#        $dir.mkdir(0o755);
    }

    IO::Path.new( $*SPEC.catfile( $dir, $file.basename.subst( / '.pod' $ /, '.html' ) ) )
        .spurt($html);
}

method !run-with-progress ($items, Routine $sub, Str $msg = q{   done}) {
    my $prog = Term::ProgressBar.new( :count( $items.elems ) )
        if $!verbose;

    my $supply = $items.Supply;

    if $!threads > 1 {
        my $sched = ThreadPoolScheduler
            .new( :max_threads($!threads) );
        $supply.schedule-on($sched);
    }

    my $i = 1;
    $supply.tap(
        sub ($item) {
            $sub($item);
            $prog.?update($i);
            $i++;
        }
    );
    $prog.?message($msg);
}

method !maybe-say (*@things) {
    return unless $!verbose;
    # We chomp in case we were given a multi-line string ending with a
    # newline.
    .say for @things.map( { .chomp } );
}

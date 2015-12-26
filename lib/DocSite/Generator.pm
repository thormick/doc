use v6;

unit class DocSite::Generator;

use DocSite::Documentable;
use DocSite::Documentable::Registry;
use DocSite::TypeGraph::Viz;
use DocSite::TypeGraph;
use File::Find;
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

has DocSite::Documentable::Registry $!registry = DocSite::Documentable::Registry.new;
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
    self!maybe-say( "Using $!threads thread" ~ ( $!threads > 1 ?? 's' !! q{} ) );
    self!maybe-blank-line;

    self!maybe-write-type-graph-images;
    self!maybe-blank-line;

    self!process-home-page;
    self!maybe-blank-line;

    self!process-language-pod;
    self!maybe-blank-line;

    self!process-type-pod;
    self!maybe-blank-line;
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
    self!maybe-say: "Writing type graph images to $image-dir ...";
    if $image-dir !~~ :e {
        $image-dir.mkdir(0o0755);
    }
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
    subgraph 'cluster: Mu children' {
        rank=same;
        style=invis;
        'Any';
        'Junction';
    }
    subgraph 'cluster: Pod:: top level' {
        rank=same;
        style=invis;
        'Pod::Config';
        'Pod::Block';
    }
    subgraph 'cluster: Date/time handling' {
        rank=same;
        style=invis;
        'Date';
        'DateTime';
        'DateTime-local-timezone';
    }
    subgraph 'cluster: Collection roles' {
        rank=same;
        style=invis;
        'Positional';
        'Associative';
        'Baggy';
    }
    END
}

method !process-home-page {
    self!maybe-say('Writing home page ...');

    my $template-file = IO::Path.new( $*SPEC.catfile( $!root, 'doc', 'index.html' ) ) ;
    my $html =
        DocSite::Pod::To::HTML.default-prelude
            .subst( /'___TITLE___'/, 'Perl 6 Documentation' )
            .subst( /'___METADATA___'/, q{} )
            ~ $template-file.slurp ~ DocSite::Pod::To::HTML.default-postlude;

    my $html-file = IO::Path.new( $*SPEC.catfile( $!root, 'html', 'index.html' ) );
    $html-file.spurt($html);
}

method !process-language-pod {
    self!process-pod-in('Language');
}

method !process-type-pod {
}

method !process-pod-in (Str $dir) {
    my @files = self!find-pod-files-in($dir);
    if $!sparse {
         @files = @files[^(@files / $!sparse).ceiling];
    }

method !process-pod-in (Str $dir) {
    self!maybe-say("Reading and processing $dir pod files ...");
    my $files = self!find-pod-files-in($dir);
    self!run-with-progress(
        $files,
        sub ($file) {
            self!process-one-pod($file);
        }
    );
}

method !find-pod-files-in (Str $in) {
    my $dir = $*SPEC.catdir( $!root, 'doc', $in );
    self!maybe-say: "Finding pod sources in $dir ...";
    my $files = find( :dir($dir), :name( rx{ '.pod' $ } ) ).cache;
    self!maybe-say("  ... found $_") for $files.values;
    return $files;
}

method !process-one-pod (IO::Path $pod-file) {
    my $doc = DocSite::Documentable.new-from-file( $pod-file, $!type-graph );
    self!spurt-html-file( $pod-file, $doc );
    $!registry.add-new($doc);
}

method !spurt-html-file (IO::Path $pod-file, DocSite::Documentable $doc) {
    my $dir = IO::Path.new( $*SPEC.catfile( $!root, 'html', $doc.kind.lc ) );
    unless $dir ~~ :e {
        $dir.mkdir(0o755);
    }

    my $html-file = $*SPEC.catfile(
        $dir,
        $pod-file.basename.subst( / '.pod' $ /, '.html' ),
    );
    IO::Path.new($html-file).spurt( $doc.html );
}

method !run-with-progress ($items, Routine $sub, Str $msg = q{   done}) {
    my $prog = Term::ProgressBar.new( :count( $items.elems ), :p )
        if $!verbose;

    my $to-run =
        $!sparse
        ?? $items.pick( ( $items.list.elems / $!sparse ).ceiling )
        !! $items;

    my $i = 1;
    my $supply = $to-run.Supply.throttle(
        $!threads,
        -> $item {
            $sub($item);
            $prog.?update($i++);
        }
    );
    $supply.wait;

    $prog.?message($msg);
}

method !maybe-blank-line {
    return unless $!verbose;
    print "\n"
}

method !maybe-say (*@things) {
    return unless $!verbose;
    # We chomp in case we were given a multi-line string ending with a
    # newline.
    .say for @things.map( { .chomp } );
}

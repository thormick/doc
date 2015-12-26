use v6;
use DocSite::Pod::To::HTML;
use DocSite::TypeGraph;
use URI::Escape;

class DocSite::Documentable {
    has Str $.name;
    has Str $.url;
    has     $.pod;
    has Str $.html;
    has Bool $.pod-is-complete;
    has Str $.summary = '';

    has Str $.kind;        # type, language doc, routine, module
    has Str @.subkinds;    # class/role/enum, sub/method, prefix/infix/...
    has Str @.categories;  # basic type, exception, operator...

    has DocSite::Documentable $.origin;

    method new-from-file ($class: IO::Path $file, DocSite::TypeGraph $type-graph) {
        use MONKEY-SEE-NO-EVAL;
        my $pod = EVAL( $file.slurp ~ "\n\$=pod[0]" );
        my $pth = DocSite::Pod::To::HTML.new;
        my $html = $pth.pod-to-html($pod);

        my $title = $pth.title
            or note "$file does not have a =TITLE";
        my $subtitle = $pth.subtitle
            or note "$file does not have a =SUBTITLE";

        my $name = $title || $file;

        my $kind = IO::Path.new( $file.dirname ).basename.lc;

        my %type-info;
        if $kind eq 'type' {
            if $type-graph.types{$name} -> $type {
                %type-info = ( :subkinds( $type.packagetype ), :categories($type.categories) );
            }
            else {
                %type-info = ( :subkinds<class> );
            }
        }

        return $class.new(
            :name($name),
            :summary($subtitle),
            :url("/$kind/{$file.basename}"),
            :pod($pod),
            :html($html),
            :pod-is-complete,
            :kind($kind),
            :subkinds($kind),
            |%type-info,
        );
    }

    my sub english-list (*@l) {
        @l > 1
            ?? @l[0..*-2].join(', ') ~ " and @l[*-1]"
            !! ~@l[0]
    }
    method human-kind() {   # SCNR
        $.kind eq 'language'
            ?? 'language documentation'
            !! @.categories eq 'operator'
            ?? "@.subkinds[] operator"
            !! english-list @.subkinds // $.kind;
    }

    method url() {
        $!url //= $.kind eq 'operator'
            ?? "/language/operators#" ~ uri_escape("@.subkinds[] $.name".subst(/\s+/, '_', :g))
            !! ("", $.kind, $.name).map(&uri_escape).join('/')
            ;
    }
    method categories() {
        @!categories //= @.subkinds
    }
}

# vim: expandtab shiftwidth=4 ft=perl6

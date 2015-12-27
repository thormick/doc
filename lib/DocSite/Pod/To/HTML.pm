use v6;
use Pod::To::HTML::Renderer;

unit class DocSite::Pod::To::HTML is Pod::To::HTML::Renderer;

use URI::Escape;

has $!selection;
has $!pod-path;

submethod BUILD (Str:D :$!selection, Str:D :$!pod-path) { }

method prelude-template {
    state $head = slurp 'template/head.html';

    my $default = callsame;
    return
        $default.subst( rx{ '</head>' }, $head ~ '</head>' )
        ~ self!header-for-selection($!selection);
}

method !header-for-selection ($current-selection) {
    state %header-for-selection = ();
    return %header-for-selection{$current-selection}
        //= self!make-header-for($current-selection);
}

method !make-header-for ($current-selection) {
    state $header = slurp 'template/header.html';

    # TODO: Generate menulist automatically
    state @menu =
        ('language',   q{}        ) => (),
        ('type',       'Types'    ) => <basic composite domain-specific exceptions>,
        ('routine',    'Routines' ) => <sub method term operator>,
#        ('module',     'Modules'  ) => (),
#        ('formalities', q{}       ) => ()
    ;

    my $menu-items = [~]
        q[<div class="menu-items dark-green">],
        @menu>>.key.map(-> ($dir, $name) {qq[
            <a class="menu-item {$dir eq $current-selection ?? "selected darker-green" !! ""}"
                href="/$dir.html">
                { $name || $dir.wordcase }
            </a>
        ]}), #"
        q[</div>];

    my $sub-menu-items = '';
    state %sub-menus = @menu>>.key>>[0] Z=> @menu>>.value;
    if %sub-menus{$current-selection} -> $_ {
        $sub-menu-items = [~]
            q[<div class="menu-items darker-green">],
            qq[<a class="menu-item" href="/$current-selection.html">All</a>],
            .map({qq[
                <a class="menu-item" href="/$current-selection\-$_.html">
                    {.wordcase}
                </a>
            ]}),
            q[</div>]
    }

    state $menu-pos = ($header ~~ /MENU/).from;

    return $header.subst('MENU', :p($menu-pos), $menu-items ~ $sub-menu-items);
}

method render-postlude {
    my $footer = slurp 'template/footer.html';
    $footer.subst-mutate(/DATETIME/, ~DateTime.now);
    my $pod-url;
    my $gh-link = q[<a href='https://github.com/perl6/doc'>perl6/doc on GitHub</a>];
    if $!pod-path eq "unknown" {
        $pod-url = "the sources at $gh-link";
    }
    else {
        $pod-url = "<a href='https://github.com/perl6/doc/raw/master/doc/$!pod-path'>$!pod-path\</a\> from $gh-link";
    }
    $footer.subst-mutate(/SOURCEURL/, $pod-url);

    return $footer;
}

#| Find links like L<die> and L<Str> and give them the proper path
method url-and-text-for (Str:D $thing) {
    given $thing {
        when /^ <[A..Z]>/ {
            return ( '/type/' ~ uri_escape($thing), $thing );
        }
        when /^ <[a..z]> | ^ <-alpha>* $/ {
            return ( '/routine/' ~ uri_escape($thing), $thing );
        }
        when / ^ '&'( \w <[[\w'-]>* ) $/ {
            return ( '/routine/' ~ uri_escape($0), $0 );
        }
    }

    callsame;
}

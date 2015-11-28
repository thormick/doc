use Pod::To::HTML::Renderer;

unit class DocSite::Pod::To::HTML is Pod::To::HTML::Renderer;

use URI::Escape;

method render-start-tag (Cool:D $tag, Bool :$nl = False, *%attr) {
    if $tag eq 'table' {
        %attr<class> = [ < table table-striped > ];
    }

    callsame;
}

method default-prelude {
    return Q:to/END/
    <!doctype html>
    <html>
    <head>
      <title>___TITLE___</title>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link rel="icon" href="/favicon.ico" type="image/x-icon">

      <link rel="stylesheet" type="text/css" href="http://perl6.org/bootstrap/css/bootstrap.min.css">
      <link rel="stylesheet" type="text/css" href="http://perl6.org/bootstrap/css/bootstrap-theme.min.css">
      <link rel="stylesheet" type="text/css" href="http://perl6.org/style.css">

      <link rel="stylesheet" type="text/css" href="/css/custom-theme/jquery-ui.css">
      <link rel="stylesheet" type="text/css" href="/css/pygments.css">
      <noscript> <style> #search { visibility: hidden; } </style> </noscript>

      ___METADATA___
    </head>
    <body class="bg" id="___top">
    END
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

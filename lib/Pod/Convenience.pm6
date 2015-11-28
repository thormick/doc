unit module Pod::Convenience;

sub first-code-block(@pod) is export {
    @pod.first(* ~~ Pod::Block::Code).contents.grep(Str).join;
}

sub pod-with-title($title, *@blocks) is export {
    Pod::Block::Named.new(
        name => "pod",
        contents => [
            flat pod-title($title), @blocks
        ]
    );
}

sub pod-title($title) is export {
    Pod::Block::Named.new(
        name    => "TITLE",
        contents => Array.new(
            Pod::Block::Para.new(
                contents => [$title],
            )
        )
    )
}

sub pod-block(*@contents) is export {
    Pod::Block::Para.new(:@contents);
}

sub pod-link($text, $url) is export {
    Pod::FormattingCode.new(
        type     => 'L',
        contents => [$text],
        meta     => [$url],
    );
}

sub pod-bold($text) is export {
    Pod::FormattingCode.new(
        type     => 'B',
        contents => [$text],
    );
}

sub pod-item(*@contents, :$level = 1) is export {
    Pod::Item.new(
        :$level,
        :@contents,
    );
}

sub pod-heading($name, :$level = 1) is export {
    Pod::Heading.new(
        :$level,
        :contents[pod-block($name)],
    );
}

sub pod-table(@contents) is export {
    Pod::Block::Table.new(
        :@contents
    )
}

sub pod-lower-headings(@content, :$to = 1) is export {
    my $by = @content.first(Pod::Heading).level;
    return @content unless $by > $to;
    my @new-content;
    for @content {
        @new-content.append($_ ~~ Pod::Heading
            ?? Pod::Heading.new: :level(.level - $by + $to) :contents[.contents]
            !! $_
        );
    }
    @new-content;
}

# vim: expandtab shiftwidth=4 ft=perl6

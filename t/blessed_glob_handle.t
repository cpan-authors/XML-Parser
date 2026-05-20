use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require IO::String };
    plan skip_all => 'IO::String not installed' if $@;
}

plan tests => 2;

use XML::Parser;

my $xml = '<root><child attr="val">text</child></root>';
my $io  = IO::String->new($xml);

my @starts;
my $parser = XML::Parser->new(
    Handlers => {
        Start => sub { shift; push @starts, shift },
    },
);

$parser->parse($io);

is_deeply( \@starts, [qw(root child)], 'IO::String parsed as stream, not string' );

$io = IO::String->new('<doc/>');
my $doc_seen = 0;
$parser->setHandlers( Start => sub { $doc_seen++ if $_[1] eq 'doc' } );
$parser->parse($io);
is( $doc_seen, 1, 'IO::String reuse works' );

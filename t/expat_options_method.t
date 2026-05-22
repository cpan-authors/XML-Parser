use strict;
use warnings;
use Test::More tests => 4;
use XML::Parser;

# Test that _expat_options correctly filters Non_Expat_Options keys
# and that both parse() and parse_start() produce working parsers
# through the shared method.

my $xml = '<root><child>text</child></root>';

# --- _expat_options returns only expat-relevant keys ---
{
    my $p = XML::Parser->new(Style => 'Tree');
    my %opts = $p->_expat_options;

    ok(!exists $opts{Non_Expat_Options}, '_expat_options excludes Non_Expat_Options');
    ok(!exists $opts{Handlers}, '_expat_options excludes Handlers');
}

# --- parse() works through _expat_options ---
{
    my @starts;
    my $p = XML::Parser->new(
        Handlers => { Start => sub { push @starts, $_[1] } },
    );
    $p->parse($xml);
    is_deeply(\@starts, ['root', 'child'], 'parse() works with extracted _expat_options');
}

# --- parse_start() works through _expat_options ---
{
    my @starts;
    my $p = XML::Parser->new(
        Handlers => { Start => sub { push @starts, $_[1] } },
    );
    my $nb = $p->parse_start;
    $nb->parse_more($xml);
    $nb->parse_done;
    is_deeply(\@starts, ['root', 'child'], 'parse_start() works with extracted _expat_options');
}

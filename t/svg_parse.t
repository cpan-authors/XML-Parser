#!/usr/bin/perl

# Verify that XML::Parser correctly handles valid SVG documents,
# including common variations (namespaces, XML declarations, BOM).
# This test was added to confirm that version 2.52 changes do not
# regress SVG parsing.  See GH#198.

use strict;
use warnings;

use Test::More;
use XML::Parser;
use File::Temp qw(tempfile);

# --- Valid SVG strings that MUST parse successfully ---

my @valid_svgs = (
    {
        name => 'minimal SVG',
        xml  => '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
    },
    {
        name => 'SVG with XML declaration',
        xml  => qq{<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>},
    },
    {
        name => 'SVG with namespace prefix',
        xml  => '<svg:svg xmlns:svg="http://www.w3.org/2000/svg"><svg:rect width="5" height="5"/></svg:svg>',
    },
    {
        name => 'SVG with attributes and nested elements',
        xml  => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g transform="translate(10,10)"><circle cx="50" cy="50" r="40"/></g></svg>',
    },
    {
        name => 'SVG with text content',
        xml  => '<svg xmlns="http://www.w3.org/2000/svg"><text x="10" y="20">Hello &amp; world</text></svg>',
    },
    {
        name => 'SVG with CDATA section',
        xml  => '<svg xmlns="http://www.w3.org/2000/svg"><style><![CDATA[.cls { fill: red; }]]></style></svg>',
    },
    {
        name => 'SVG with UTF-8 BOM',
        xml  => "\xEF\xBB\xBF" . '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg"/>',
    },
);

# --- Invalid inputs that should fail at byte 0 ---

my @invalid_byte0 = (
    {
        name   => 'gzip-compressed data',
        xml    => "\x1F\x8B\x08\x00" . "fake gzip SVG data",
        reason => 'binary gzip header is not valid XML',
    },
    {
        name   => 'null byte',
        xml    => "\x00<svg/>",
        reason => 'null byte before XML content',
    },
    {
        name   => 'empty string',
        xml    => '',
        reason => 'no content to parse',
    },
);

plan tests => scalar(@valid_svgs) * 2 + scalar(@invalid_byte0);

# Test valid SVGs parse as strings
for my $case (@valid_svgs) {
    my $p = XML::Parser->new();
    my $ok = eval { $p->parse($case->{xml}); 1 };
    ok($ok, "string parse: $case->{name}");
}

# Test valid SVGs parse from files (parsefile path)
for my $case (@valid_svgs) {
    my ($fh, $filename) = tempfile(SUFFIX => '.svg', UNLINK => 1);
    binmode($fh);
    print $fh $case->{xml};
    close $fh;

    my $p  = XML::Parser->new();
    my $ok = eval { $p->parsefile($filename); 1 };
    ok($ok, "file parse: $case->{name}")
      or diag("Error: $@");
}

# Test that invalid byte-0 inputs fail (they always would, regardless of version)
for my $case (@invalid_byte0) {
    my $p = XML::Parser->new();
    eval { $p->parse($case->{xml}) };
    ok($@, "rejects $case->{name}: $case->{reason}");
}

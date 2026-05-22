#!/usr/bin/perl

# Test SSRF protection in the LWP external entity handler.
# Verifies URL scheme whitelist and private IP blocking.
# See GitHub issue #275.

use strict;
use warnings;

use Test::More;
use XML::Parser;

eval { require LWP::UserAgent; require URI; };
if ($@) {
    plan skip_all => 'LWP::UserAgent not installed';
}

plan tests => 14;

# Helper: parse XML with an external entity pointing to $uri
# Returns error message on failure, empty string on success.
sub parse_with_entity {
    my ($uri, %opts) = @_;
    my $xml = qq{<!DOCTYPE foo [\n  <!ENTITY ext SYSTEM "$uri">\n]>\n<foo>&ext;</foo>};
    my $p = XML::Parser->new(%opts);
    eval { $p->parse($xml) };
    return $@ || '';
}

# --- URL scheme whitelist ---

# Dangerous schemes must be rejected
{
    my $err = parse_with_entity('gopher://evil.example.com/');
    like($err, qr/scheme.*not allowed|not permitted/i,
        'gopher:// scheme rejected');
}

{
    my $err = parse_with_entity('ftp://evil.example.com/data');
    like($err, qr/scheme.*not allowed|not permitted/i,
        'ftp:// scheme rejected');
}

{
    my $err = parse_with_entity('data:text/plain,hello');
    like($err, qr/scheme.*not allowed|not permitted/i,
        'data: scheme rejected');
}

{
    my $err = parse_with_entity('dict://evil.example.com/');
    like($err, qr/scheme.*not allowed|not permitted/i,
        'dict:// scheme rejected');
}

# --- Private IP blocking ---

{
    my $err = parse_with_entity('http://169.254.169.254/latest/meta-data/');
    like($err, qr/private|blocked|not allowed/i,
        'link-local 169.254.x.x blocked');
}

{
    my $err = parse_with_entity('http://127.0.0.1/secret');
    like($err, qr/private|blocked|not allowed/i,
        'loopback 127.0.0.1 blocked');
}

{
    my $err = parse_with_entity('http://10.0.0.1/internal');
    like($err, qr/private|blocked|not allowed/i,
        '10.x.x.x private range blocked');
}

{
    my $err = parse_with_entity('http://192.168.1.1/router');
    like($err, qr/private|blocked|not allowed/i,
        '192.168.x.x private range blocked');
}

{
    my $err = parse_with_entity('http://172.16.0.1/internal');
    like($err, qr/private|blocked|not allowed/i,
        '172.16.x.x private range blocked');
}

{
    my $err = parse_with_entity('http://[::1]/secret');
    like($err, qr/private|blocked|not allowed/i,
        'IPv6 loopback [::1] blocked');
}

# --- NoNetwork option ---

{
    my $err = parse_with_entity('http://example.com/foo.xml', NoNetwork => 1);
    like($err, qr/network.*disabled|not allowed|NoNetwork/i,
        'NoNetwork blocks http:// URLs');
}

{
    my $err = parse_with_entity('https://example.com/foo.xml', NoNetwork => 1);
    like($err, qr/network.*disabled|not allowed|NoNetwork/i,
        'NoNetwork blocks https:// URLs');
}

# --- file:// still works with NoNetwork ---
# (file_ext_ent_handler is used for local files)

use File::Temp qw(tempfile);
my ($fh, $entfile) = tempfile(UNLINK => 1, SUFFIX => '.ent');
print $fh "local content";
close $fh;

{
    my $chardata = '';
    my $xml = qq{<!DOCTYPE foo [\n  <!ENTITY ext SYSTEM "$entfile">\n]>\n<foo>&ext;</foo>};
    my $p = XML::Parser->new(
        NoNetwork => 1,
        Handlers  => { Char => sub { $chardata .= $_[1] } },
    );
    eval { $p->parse($xml) };
    is($@, '', 'NoNetwork allows local file entities');
    is($chardata, 'local content', 'NoNetwork: local file content correct');
}

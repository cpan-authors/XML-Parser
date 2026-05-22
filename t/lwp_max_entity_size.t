#!/usr/bin/perl

# Test MaxEntitySize option for LWP external entity handler.
# Mocks LWP::UserAgent to avoid network calls.

use strict;
use warnings;

use Test::More;
use XML::Parser;

BEGIN {
    eval { require LWP::UserAgent; require URI; };
    if ($@) {
        plan skip_all => 'LWP::UserAgent or URI not installed';
    }
    plan tests => 8;
}

my $xml_with_entity = <<'XML';
<!DOCTYPE foo [
  <!ENTITY ext SYSTEM "http://example.com/entity.xml">
]>
<foo>&ext;</foo>
XML

# Mock LWP::UserAgent to capture max_size and return controlled responses
{
    package MockResponse;
    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }
    sub is_error       { return $_[0]->{is_error} }
    sub content        { return $_[0]->{content} }
    sub status_line    { return $_[0]->{status_line} || '200 OK' }
    sub header         { return $_[0]->{headers}{ $_[1] } }

    package MockUA;
    my $last_max_size;
    my $mock_response;
    sub new            { $last_max_size = undef; bless {}, $_[0] }
    sub env_proxy      { }
    sub max_size       { $last_max_size = $_[1] if @_ > 1; $last_max_size }
    sub request        { return $mock_response }
    sub _last_max_size { $last_max_size }
    sub _set_response  { $mock_response = $_[1] }
}

# Patch LWP::UserAgent::new to return MockUA
my $orig_lwp_new = \&LWP::UserAgent::new;
{
    no warnings 'redefine';
    *LWP::UserAgent::new = sub { MockUA->new() };
}

# Force reload of LWPExternEnt.pl so it picks up mock
$XML::Parser::LWP_load_failed = 0;

# Test 1: Default MaxEntitySize applied (10MB)
{
    MockUA->_set_response(MockResponse->new(
        is_error => 0,
        content  => '<bar/>',
    ));

    my $chardata = '';
    my $p = XML::Parser->new(
        Handlers => { Char => sub { $chardata .= $_[1] } },
    );

    eval { $p->parse($xml_with_entity) };
    is(MockUA->_last_max_size(), 10_485_760,
       'default MaxEntitySize is 10MB');
}

# Test 2: Custom MaxEntitySize is applied
{
    MockUA->_set_response(MockResponse->new(
        is_error => 0,
        content  => '<bar/>',
    ));

    my $p = XML::Parser->new(
        MaxEntitySize => 5_000_000,
        Handlers => { Char => sub { } },
    );

    eval { $p->parse($xml_with_entity) };
    is(MockUA->_last_max_size(), 5_000_000,
       'custom MaxEntitySize is respected');
}

# Test 3: MaxEntitySize => 0 disables limit
{
    MockUA->_set_response(MockResponse->new(
        is_error => 0,
        content  => '<bar/>',
    ));

    my $p = XML::Parser->new(
        MaxEntitySize => 0,
        Handlers => { Char => sub { } },
    );

    eval { $p->parse($xml_with_entity) };
    is(MockUA->_last_max_size(), undef,
       'MaxEntitySize => 0 disables size limit');
}

# Test 4: Client-Aborted response triggers error
{
    MockUA->_set_response(MockResponse->new(
        is_error    => 0,
        content     => 'partial...',
        headers     => { 'Client-Aborted' => 'max_size' },
        status_line => '200 OK',
    ));

    my $p = XML::Parser->new(
        MaxEntitySize => 1_000,
        Handlers => { Char => sub { } },
    );

    eval { $p->parse($xml_with_entity) };
    like($@, qr/exceeded/i,
         'Client-Aborted response causes parse error');
}

# Test 5: Normal is_error still works
{
    MockUA->_set_response(MockResponse->new(
        is_error    => 1,
        content     => '',
        status_line => '404 Not Found',
    ));

    my $p = XML::Parser->new(
        Handlers => { Char => sub { } },
    );

    eval { $p->parse($xml_with_entity) };
    like($@, qr/404 Not Found/,
         'HTTP error still reported');
}

# Test 6: Successful fetch with custom limit returns content
{
    MockUA->_set_response(MockResponse->new(
        is_error => 0,
        content  => 'hello world',
    ));

    my $chardata = '';
    my $p = XML::Parser->new(
        MaxEntitySize => 1_000_000,
        Handlers => { Char => sub { $chardata .= $_[1] } },
    );

    eval { $p->parse($xml_with_entity) };
    is($@, '', 'successful fetch with MaxEntitySize does not error');
    is($chardata, 'hello world', 'entity content returned correctly');
}

# Test 7: MaxEntitySize persists across multiple entity fetches
{
    my $call_count = 0;
    MockUA->_set_response(MockResponse->new(
        is_error => 0,
        content  => 'ent',
    ));

    my $xml_multi = <<'XML';
<!DOCTYPE foo [
  <!ENTITY a SYSTEM "http://example.com/a.xml">
  <!ENTITY b SYSTEM "http://example.com/b.xml">
]>
<foo>&a;&b;</foo>
XML

    my $p = XML::Parser->new(
        MaxEntitySize => 2_000_000,
        Handlers => { Char => sub { } },
    );

    eval { $p->parse($xml_multi) };
    is(MockUA->_last_max_size(), 2_000_000,
       'MaxEntitySize applied consistently across entities');
}

# Restore original
{
    no warnings 'redefine';
    *LWP::UserAgent::new = $orig_lwp_new;
}

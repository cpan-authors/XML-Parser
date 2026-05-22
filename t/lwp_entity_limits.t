#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

BEGIN {
    eval { require LWP::UserAgent; require HTTP::Response; 1 }
      or plan skip_all => 'LWP::UserAgent required for this test';
}

plan tests => 9;

use XML::Parser;

my $xml_with_entity = <<'XML';
<!DOCTYPE foo [
  <!ENTITY ext SYSTEM "http://example.com/entity.txt">
]>
<foo>&ext;</foo>
XML

# Intercept LWP::UserAgent to capture configuration and return mock responses
my %captured_ua_settings;
my $mock_response;

{
    no warnings 'redefine';

    my $orig_new = \&LWP::UserAgent::new;
    *LWP::UserAgent::new = sub {
        my $ua = $orig_new->(@_);
        %captured_ua_settings = ();
        return $ua;
    };

    my $orig_max_size = \&LWP::UserAgent::max_size;
    *LWP::UserAgent::max_size = sub {
        if (@_ > 1) {
            $captured_ua_settings{max_size} = $_[1];
        }
        return $orig_max_size->(@_);
    };

    my $orig_timeout = \&LWP::UserAgent::timeout;
    *LWP::UserAgent::timeout = sub {
        if (@_ > 1) {
            $captured_ua_settings{timeout} = $_[1];
        }
        return $orig_timeout->(@_);
    };

    *LWP::UserAgent::request = sub {
        return $mock_response;
    };
}

sub make_response {
    my (%opts) = @_;
    my $res = HTTP::Response->new($opts{code} // 200, $opts{message} // 'OK');
    $res->content($opts{content} // '');
    $res->header('Client-Aborted' => $opts{client_aborted})
      if $opts{client_aborted};
    return $res;
}

# Test 1-2: Default limits applied (1MB max_size, 30s timeout)
{
    %captured_ua_settings = ();
    $mock_response = make_response(content => 'hello');

    my $chardata = '';
    my $p = XML::Parser->new(
        Handlers => { Char => sub { $chardata .= $_[1] } },
    );
    eval { $p->parse($xml_with_entity) };

    is($captured_ua_settings{max_size}, 1_048_576,
       'Default max_size is 1MB');
    is($captured_ua_settings{timeout}, 30,
       'Default timeout is 30 seconds');
}

# Test 3-4: Custom limits honored
{
    %captured_ua_settings = ();
    $mock_response = make_response(content => 'hello');

    my $p = XML::Parser->new(
        LWP_MaxEntitySize => 500_000,
        LWP_Timeout       => 10,
        Handlers          => { Char => sub {} },
    );
    eval { $p->parse($xml_with_entity) };

    is($captured_ua_settings{max_size}, 500_000,
       'Custom max_size honored');
    is($captured_ua_settings{timeout}, 10,
       'Custom timeout honored');
}

# Test 5: Normal response parses successfully
{
    $mock_response = make_response(content => 'entity content');

    my $chardata = '';
    my $p = XML::Parser->new(
        Handlers => { Char => sub { $chardata .= $_[1] } },
    );
    eval { $p->parse($xml_with_entity) };
    is($@, '', 'Normal response parses without error');
}

# Test 6-7: Truncated response (Client-Aborted) causes parse error
{
    $mock_response = make_response(
        content        => 'x' x 100,
        client_aborted => 'die',
    );

    my $p = XML::Parser->new(
        LWP_MaxEntitySize => 1024,
        Handlers          => { Char => sub {} },
    );
    eval { $p->parse($xml_with_entity) };
    like($@, qr/entity too large/i,
         'Truncated response causes parse error');
    like($@, qr/1024/,
         'Error message includes size limit');
}

# Test 8: Disable max_size with 0
{
    %captured_ua_settings = ();
    $mock_response = make_response(content => 'hello');

    my $p = XML::Parser->new(
        LWP_MaxEntitySize => 0,
        Handlers          => { Char => sub {} },
    );
    eval { $p->parse($xml_with_entity) };

    ok(!exists $captured_ua_settings{max_size},
       'max_size not set when LWP_MaxEntitySize is 0');
}

# Test 9: HTTP error still reported correctly
{
    $mock_response = make_response(code => 404, message => 'Not Found');

    my $p = XML::Parser->new(
        Handlers => { Char => sub {} },
    );
    eval { $p->parse($xml_with_entity) };
    like($@, qr/404/,
         'HTTP errors still reported');
}

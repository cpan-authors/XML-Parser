#!/usr/bin/perl

# Test that file_ext_ent_handler restricts absolute paths and directory
# traversal in external entity SYSTEM identifiers to prevent XXE file
# disclosure attacks (GitHub issue #278).

use strict;
use warnings;

use Test::More tests => 14;
use File::Temp qw(tempfile);

use XML::Parser;

sub xml_with_entity_path {
    my ($path) = @_;
    return qq{<!DOCTYPE foo [\n  <!ENTITY x SYSTEM "$path">\n]>\n<foo>&x;</foo>};
}

# --- Absolute paths must be blocked ---

my @abs_cases = (
    [ '/etc/passwd',       'absolute Unix path' ],
    [ '/tmp/anything',     'absolute /tmp path' ],
    [ 'C:\\Windows\\win.ini', 'Windows drive letter path' ],
);

for my $case (@abs_cases) {
    my ($path, $label) = @$case;
    my $p = XML::Parser->new( NoLWP => 1 );
    eval { $p->parse( xml_with_entity_path($path) ) };
    like( $@, qr/absolute path/i, "blocked: $label" );
}

# --- Directory traversal must be blocked ---

my @trav_cases = (
    [ '../etc/passwd',               'parent traversal' ],
    [ '../../etc/passwd',            'double parent traversal' ],
    [ 'subdir/../../etc/passwd',     'traversal after subdir' ],
    [ '..\\Windows\\System32\\config', 'Windows-style traversal' ],
);

for my $case (@trav_cases) {
    my ($path, $label) = @$case;
    my $p = XML::Parser->new( NoLWP => 1 );
    eval { $p->parse( xml_with_entity_path($path) ) };
    like( $@, qr/directory traversal/i, "blocked: $label" );
}

# --- Normal relative paths must NOT be blocked ---

{
    my $p = XML::Parser->new( NoLWP => 1 );
    eval { $p->parse( xml_with_entity_path('some_entity.ent') ) };
    unlike( $@, qr/absolute path|directory traversal/i,
        'simple relative path not blocked' );
}

{
    my $p = XML::Parser->new( NoLWP => 1 );
    eval { $p->parse( xml_with_entity_path('subdir/entity.ent') ) };
    unlike( $@, qr/absolute path|directory traversal/i,
        'nested relative path not blocked' );
}

# --- UnsafeExternalEntities => 1 allows absolute paths ---

{
    my $p = XML::Parser->new( NoLWP => 1, UnsafeExternalEntities => 1 );
    eval { $p->parse( xml_with_entity_path('/nonexistent/file.ent') ) };
    unlike( $@, qr/absolute path/i,
        'absolute path allowed with UnsafeExternalEntities' );
    like( $@, qr/Failed to open/i,
        'UnsafeExternalEntities: fails with file-not-found, not path restriction' );
}

# --- UnsafeExternalEntities => 1 allows traversal ---

{
    my $p = XML::Parser->new( NoLWP => 1, UnsafeExternalEntities => 1 );
    eval { $p->parse( xml_with_entity_path('../nonexistent.ent') ) };
    unlike( $@, qr/directory traversal/i,
        'traversal allowed with UnsafeExternalEntities' );
}

# --- Absolute path works end-to-end with UnsafeExternalEntities ---

{
    my ($fh, $entfile) = tempfile( UNLINK => 1, SUFFIX => '.ent' );
    print $fh "safe content";
    close $fh;

    my $chardata = '';
    my $p = XML::Parser->new(
        NoLWP                  => 1,
        UnsafeExternalEntities => 1,
        Handlers               => { Char => sub { $chardata .= $_[1] } },
    );
    eval { $p->parse( xml_with_entity_path($entfile) ) };
    is( $@, '', 'absolute path with UnsafeExternalEntities parses OK' );
    is( $chardata, 'safe content',
        'absolute path entity content read correctly' );
}

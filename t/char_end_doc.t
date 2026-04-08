BEGIN { print "1..4\n"; }
END { print "not ok 1\n" unless $loaded; }
use XML::Parser;
$loaded = 1;
print "ok 1\n";

# Regression tests for character data after root closing tag
# (rt.cpan.org #46685 / GitHub issue #47)
#
# Libexpat sends character data outside the root element to the
# DefaultHandler.  Redirecting it to the Char handler was attempted
# (PR #118) but broke tree-building modules like XML::DOM, XML::Twig,
# and XML::XPath — reverted in PR #214.  The default handler must
# remain the sole recipient of post-root character data.

my @char_data;
my @dflt_data;

sub char_handler {
    my ( $xp, $data ) = @_;
    push @char_data, $data;
}

sub dflt_handler {
    my ( $xp, $data ) = @_;
    push @dflt_data, $data;
}

my $p = XML::Parser->new(
    Handlers => {
        Char    => \&char_handler,
        Default => \&dflt_handler,
    }
);

$p->parse("<doc>foo</doc>\n \n");

# Test 2: trailing whitespace must go to Default handler (not Char)
# Redirecting to Char breaks XML::DOM with HIERARCHY_REQUEST_ERR
my $dflt_trailing = join( '', grep { /^\s+$/ } @dflt_data );
if ( $dflt_trailing eq "\n \n" ) {
    print "ok 2\n";
}
else {
    print "not ok 2 # Default handler did not receive trailing whitespace, got: '$dflt_trailing'\n";
}

# Test 3: Char handler should NOT receive the trailing whitespace
my $char_trailing = join( '', grep { /^\s+$/ } @char_data );
if ( $char_trailing eq '' ) {
    print "ok 3\n";
}
else {
    print "not ok 3 # Char handler received trailing whitespace: '$char_trailing'\n";
}

# Test 4: content INSIDE the root element that goes to Default handler
# must NOT be redirected to Char handler (e.g. markup, entity decls).
# This ensures we only reroute outside the root element.
my @inner_char;
my @inner_dflt;

my $p2 = XML::Parser->new(
    Handlers => {
        Char    => sub { push @inner_char, $_[1] },
        Default => sub { push @inner_dflt, $_[1] },
    }
);

# Parse a doc with a comment (which goes to Default inside root)
$p2->parse("<doc><!-- a comment -->text</doc>");

my $has_comment_in_dflt = grep { /a comment/ } @inner_dflt;
if ($has_comment_in_dflt) {
    print "ok 4\n";
}
else {
    print "not ok 4 # Comment inside root should stay in Default handler\n";
}

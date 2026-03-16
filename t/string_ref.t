BEGIN { print "1..4\n"; }
END { print "not ok 1\n" unless $loaded; }
use XML::Parser;
$loaded = 1;
print "ok 1\n";

# Test parsing a string passed by reference (issue #18)

my $xml = '<root><child attr="val">text</child></root>';
my $count = 0;

my $parser = XML::Parser->new(
    Handlers => {
        Start => sub { $count++ },
    }
);

# Test 2: parse with scalar reference succeeds
eval { $parser->parse(\$xml) };
if ($@) {
    print "not ok 2 # parse(\\$xml) failed: $@\n";
} else {
    print "ok 2\n";
}

# Test 3: correct number of elements parsed
if ($count == 2) {
    print "ok 3\n";
} else {
    print "not ok 3 # expected 2 start elements, got $count\n";
}

# Test 4: original string is not modified
if ($xml eq '<root><child attr="val">text</child></root>') {
    print "ok 4\n";
} else {
    print "not ok 4 # original string was modified\n";
}

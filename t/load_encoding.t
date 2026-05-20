use strict;
use warnings;
use Test::More;
use File::Temp ();
use File::Spec ();

use XML::Parser;
use XML::Parser::Expat;

# Verify encoding files exist in the search path before testing.
my @enc_path = @XML::Parser::Expat::Encoding_Path;
my $found_enc_dir;
for my $dir (@enc_path) {
    if ( -f File::Spec->catfile( $dir, 'iso-8859-2.enc' ) ) {
        $found_enc_dir = $dir;
        last;
    }
}

unless ($found_enc_dir) {
    plan skip_all => 'No encoding files found in @Encoding_Path';
}

plan tests => 17;

# ---------------------------------------------------------------
# Test 1-2: Basic load by short name (uses @Encoding_Path search)
# ---------------------------------------------------------------
{
    my $name = eval { XML::Parser::Expat::load_encoding('iso-8859-2') };
    ok( !$@, 'load_encoding iso-8859-2 succeeds' )
        or diag("Error: $@");
    is( $name, 'ISO-8859-2', 'load_encoding returns encoding name from file' );
}

# ---------------------------------------------------------------
# Test 3: Case-insensitive — uppercase is lowered (line 102)
# ---------------------------------------------------------------
{
    my $name = eval { XML::Parser::Expat::load_encoding('ISO-8859-2') };
    ok( !$@, 'load_encoding with uppercase name succeeds' )
        or diag("Error: $@");
}

# ---------------------------------------------------------------
# Test 4: Auto-append .enc suffix
# ---------------------------------------------------------------
{
    # Already appends .enc to bare name; verify it works without it
    my $name = eval { XML::Parser::Expat::load_encoding('windows-1252') };
    ok( !$@, 'load_encoding auto-appends .enc suffix' )
        or diag("Error: $@");
}

# ---------------------------------------------------------------
# Test 5: Explicit .enc suffix is not doubled
# ---------------------------------------------------------------
{
    my $name = eval { XML::Parser::Expat::load_encoding('koi8-r.enc') };
    ok( !$@, 'load_encoding with explicit .enc suffix succeeds' )
        or diag("Error: $@");
}

# ---------------------------------------------------------------
# Test 6-7: Absolute path bypasses @Encoding_Path search
# ---------------------------------------------------------------
{
    my $abs = File::Spec->catfile( $found_enc_dir, 'iso-8859-5.enc' );
    my $name = eval { XML::Parser::Expat::load_encoding($abs) };
    ok( !$@, 'load_encoding with absolute path succeeds' )
        or diag("Error: $@");
    is( $name, 'ISO-8859-5', 'absolute path load returns encoding name from file' );
}

# ---------------------------------------------------------------
# Test 8: File not found raises an error
# ---------------------------------------------------------------
{
    eval { XML::Parser::Expat::load_encoding('nonexistent-encoding-xyz') };
    like( $@, qr/Couldn't open encmap/, 'load_encoding croaks on missing file' );
}

# ---------------------------------------------------------------
# Test 9: Invalid encoding file content raises an error
# The filename part is lowercased by load_encoding, so use a
# temp directory with an explicitly lowercase filename.
# ---------------------------------------------------------------
{
    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'bad-encoding.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    print $fh "this is not a valid encoding map\n";
    close $fh;

    eval { XML::Parser::Expat::load_encoding($file) };
    like( $@, qr/isn't an encmap file/, 'load_encoding croaks on invalid file' );
}

# ---------------------------------------------------------------
# Test 10: Empty file raises an error
# ---------------------------------------------------------------
{
    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'empty-encoding.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    close $fh;

    eval { XML::Parser::Expat::load_encoding($file) };
    like( $@, qr/isn't an encmap file/, 'load_encoding croaks on empty file' );
}

# ---------------------------------------------------------------
# Test 11-12: Loaded encoding is usable with ProtocolEncoding
# ---------------------------------------------------------------
{
    my $name = eval { XML::Parser::Expat::load_encoding('windows-1251') };
    ok( !$@, 'load_encoding windows-1251 succeeds' )
        or diag("Error: $@");

    # Parse a document that declares windows-1251 encoding
    my $xml = qq{<?xml version="1.0" encoding="windows-1251"?>\n<doc/>};
    my $parsed;
    my $p = XML::Parser->new(
        ProtocolEncoding => 'windows-1251',
        Handlers         => { Start => sub { $parsed = 1 } },
    );
    eval { $p->parse($xml) };
    ok( $parsed, 'loaded encoding is usable for parsing' );
}

# ---------------------------------------------------------------
# Test 13-14: Multiple encodings can be loaded
# ---------------------------------------------------------------
{
    my $n1 = eval { XML::Parser::Expat::load_encoding('iso-8859-3') };
    my $n2 = eval { XML::Parser::Expat::load_encoding('iso-8859-4') };
    ok( defined $n1, 'first encoding loaded' );
    ok( defined $n2, 'second encoding loaded' );
}

# ---------------------------------------------------------------
# Test 15: bmap_start + len exceeding bmsize is rejected
# Crafts a binary encmap with one PrefixMap whose bmap_start + len
# overflows the bytemap, which would cause an out-of-bounds read
# in convert_to_unicode if not caught at load time.
# ---------------------------------------------------------------
{
    my $MAGIC  = 0xfeebface;
    my $pfsize = 1;
    my $bmsize = 10;

    my $header = pack("N", $MAGIC)
               . pack("a40", "BADBMAP")
               . pack("n", $pfsize)
               . pack("n", $bmsize)
               . pack("N256", (0) x 256);

    # bmap_start=5, len=10 => 5+10=15 > bmsize=10
    my $pfx = pack("C", 0)              # min
            . pack("C", 10)             # len
            . pack("n", 5)              # bmap_start
            . ("\0" x 32)               # ispfx
            . ("\0" x 32);              # ischar

    my $bm = pack("n10", (0) x 10);

    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'badbmap.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    binmode $fh;
    print $fh $header . $pfx . $bm;
    close $fh;

    eval { XML::Parser::Expat::load_encoding($file) };
    like( $@, qr/isn't an encmap file/,
          'bmap_start + len > bmsize is rejected' );
}

# ---------------------------------------------------------------
# Test 16: bmap_start overflow with len=0 (meaning 256) is rejected
# ---------------------------------------------------------------
{
    my $MAGIC  = 0xfeebface;
    my $pfsize = 1;
    my $bmsize = 100;

    my $header = pack("N", $MAGIC)
               . pack("a40", "BADBMAP2")
               . pack("n", $pfsize)
               . pack("n", $bmsize)
               . pack("N256", (0) x 256);

    # bmap_start=0, len=0 (means 256) => 0+256=256 > bmsize=100
    my $pfx = pack("C", 0)              # min
            . pack("C", 0)              # len (0 => 256)
            . pack("n", 0)              # bmap_start
            . ("\0" x 32)               # ispfx
            . ("\0" x 32);              # ischar

    my $bm = pack("n100", (0) x 100);

    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'badbmap2.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    binmode $fh;
    print $fh $header . $pfx . $bm;
    close $fh;

    eval { XML::Parser::Expat::load_encoding($file) };
    like( $@, qr/isn't an encmap file/,
          'bmap_start + 256 (len=0) > bmsize is rejected' );
}

# ---------------------------------------------------------------
# Test 17: Valid bmap_start + len within bmsize is accepted
# ---------------------------------------------------------------
{
    my $MAGIC  = 0xfeebface;
    my $pfsize = 1;
    my $bmsize = 20;

    my $header = pack("N", $MAGIC)
               . pack("a40", "GOODBMAP")
               . pack("n", $pfsize)
               . pack("n", $bmsize)
               . pack("N256", (0) x 256);

    # bmap_start=5, len=10 => 5+10=15 <= bmsize=20 => valid
    my $pfx = pack("C", 0)              # min
            . pack("C", 10)             # len
            . pack("n", 5)              # bmap_start
            . ("\0" x 32)               # ispfx
            . ("\0" x 32);              # ischar

    my $bm = pack("n20", (0) x 20);

    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'goodbmap.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    binmode $fh;
    print $fh $header . $pfx . $bm;
    close $fh;

    my $name = eval { XML::Parser::Expat::load_encoding($file) };
    ok( !$@, 'valid bmap_start within bmsize is accepted' )
        or diag("Error: $@");
}

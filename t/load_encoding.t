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

plan tests => 18;

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

# ---------------------------------------------------------------
# Test 18: bytemap entry pointing beyond prefixes_size does not crash
# Crafts a multi-byte encoding where a bytemap entry contains an
# index >= prefixes_size. Without bounds checking in convert_to_unicode,
# this would cause an out-of-bounds read on the prefixes array.
# ---------------------------------------------------------------
{
    my $MAGIC  = 0xfeebface;
    my $pfsize = 2;
    my $bmsize = 512;  # 256 entries for each of 2 prefix maps

    # firstmap: byte 0x80-0xFF are 2-byte prefixes (value = -2),
    # bytes 0x00-0x7F map to themselves (ASCII)
    my @firstmap;
    for my $i (0..127) { $firstmap[$i] = $i; }
    for my $i (128..255) { $firstmap[$i] = -2; }

    my $header = pack("N", $MAGIC)
               . pack("a40", "BADPFXIDX")
               . pack("n", $pfsize)
               . pack("n", $bmsize)
               . pack("N256", @firstmap);

    # PrefixMap 0: covers bytes 0x80-0xFF, marks all as prefixes
    my $ispfx0  = "\0" x 32;
    my $ischar0 = "\0" x 32;
    for my $byte (0x80..0xFF) {
        vec($ispfx0, $byte, 1) = 1;
    }
    my $pfx0 = pack("C", 0x80)         # min
             . pack("C", 128)           # len (128 bytes: 0x80-0xFF)
             . pack("n", 0)             # bmap_start
             . $ispfx0
             . $ischar0;

    # PrefixMap 1: covers bytes 0x40-0xBF, marks all as characters
    my $ispfx1  = "\0" x 32;
    my $ischar1 = "\0" x 32;
    for my $byte (0x40..0xBF) {
        vec($ischar1, $byte, 1) = 1;
    }
    my $pfx1 = pack("C", 0x40)         # min
             . pack("C", 128)           # len
             . pack("n", 256)           # bmap_start
             . $ispfx1
             . $ischar1;

    # Bytemap: first 256 entries (for pfx0) all point to index 99
    # which is WAY beyond prefixes_size=2 — this is the poison value
    my @bm;
    for my $i (0..255) { $bm[$i] = 99; }  # invalid prefix index
    # Next 256 entries (for pfx1) map to Unicode codepoints
    for my $i (0..255) { $bm[256 + $i] = 0x4E00 + $i; }

    my $bm_data = pack("n$bmsize", @bm);

    my $tmpdir = File::Temp->newdir();
    my $file   = File::Spec->catfile( $tmpdir, 'badpfxidx.enc' );
    open( my $fh, '>', $file ) or die "Cannot create $file: $!";
    binmode $fh;
    print $fh $header . $pfx0 . $pfx1 . $bm_data;
    close $fh;

    my $name = eval { XML::Parser::Expat::load_encoding($file) };
    ok( !$@, 'encoding with out-of-bounds bytemap index loads without crash' )
        or diag("Error: $@");

    # Now actually parse with this encoding to exercise convert_to_unicode
    if ($name) {
        my $xml = qq{<?xml version="1.0" encoding="BADPFXIDX"?>\n<doc>\x80\x80</doc>};
        my $p = XML::Parser->new(
            Handlers => { Start => sub {} },
        );
        # Should not crash — the bounds check makes convert_to_unicode
        # return -1 for the invalid prefix index, causing a parse error
        eval { $p->parse($xml) };
        # We don't care whether parsing succeeds or fails with an error,
        # only that it doesn't segfault/crash
    }
}

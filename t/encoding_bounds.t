use strict;
use warnings;
use Test::More;
use File::Temp ();
use File::Spec ();

use XML::Parser;
use XML::Parser::Expat;

# Helper: build a binary .enc file from components
sub build_enc {
    my (%args) = @_;

    my $MAGIC  = 0xfeebface;
    my $pfsize = $args{pfsize} || 0;
    my $bmsize = $args{bmsize} || 0;
    my $name   = $args{name}   || "TESTENC";

    # firstmap: 256 entries, each a network-order 32-bit int
    my @firstmap = @{ $args{firstmap} || [ (0) x 256 ] };

    my $header = pack("N", $MAGIC)
               . pack("a40", $name)
               . pack("n", $pfsize)
               . pack("n", $bmsize)
               . pack("N256", @firstmap);

    my $pfx_data = '';
    for my $p (@{ $args{prefixes} || [] }) {
        $pfx_data .= pack("C", $p->{min})
                    . pack("C", $p->{len})
                    . pack("n", $p->{bmap_start})
                    . $p->{ispfx}
                    . $p->{ischar};
    }

    my $bm_data = '';
    for my $val (@{ $args{bytemap} || [] }) {
        $bm_data .= pack("n", $val);
    }

    return $header . $pfx_data . $bm_data;
}

sub write_enc {
    my ($dir, $filename, $data) = @_;
    my $file = File::Spec->catfile($dir, $filename);
    open(my $fh, '>', $file) or die "Cannot create $file: $!";
    binmode $fh;
    print $fh $data;
    close $fh;
    return $file;
}

# ---------------------------------------------------------------
# Test 1: Bytemap entry used as prefix index exceeds prefixes_size
# — must be rejected at load time
# ---------------------------------------------------------------
{
    # Build an enc with 1 prefix map entry, bytemap size 256.
    # PrefixMap[0]: min=0x80, len=2, bmap_start=0
    # ispfx: bit set for byte 0x80 (indicates prefix)
    # ischar: bit set for byte 0x81 (indicates character)
    # bytemap[0] = 99 (INVALID: only 1 prefix, index must be < 1)
    # bytemap[1] = 0x4E00 (a valid Unicode codepoint)

    my @ispfx  = (0) x 32;
    my @ischar = (0) x 32;
    # byte 0x80 => bndx=16, bmsk=1 => ispfx[16] |= 1
    $ispfx[16] = 1;
    # byte 0x81 => bndx=16, bmsk=2 => ischar[16] |= 2
    $ischar[16] = 2;

    my @firstmap = (0) x 256;
    # firstmap[0x80] = -2 means 2-byte sequence starting with 0x80
    $firstmap[0x80] = unpack("N", pack("N", -2));

    my $enc_data = build_enc(
        name     => "BADPFXIDX",
        pfsize   => 1,
        bmsize   => 256,
        firstmap => \@firstmap,
        prefixes => [{
            min        => 0x80,
            len        => 2,
            bmap_start => 0,
            ispfx      => pack("C32", @ispfx),
            ischar     => pack("C32", @ischar),
        }],
        bytemap  => [ 99, 0x4E00, (0) x 254 ],
    );

    my $tmpdir = File::Temp->newdir();
    my $file = write_enc($tmpdir, 'badpfxidx.enc', $enc_data);

    eval { XML::Parser::Expat::load_encoding($file) };
    like($@, qr/isn't an encmap file/,
         'bytemap prefix index exceeding prefixes_size is rejected');
}

# ---------------------------------------------------------------
# Test 2: Valid bytemap prefix indices are accepted
# ---------------------------------------------------------------
{
    # 2 prefix maps. PrefixMap[0] has ispfx bit for 0x80 with
    # bytemap value 1 (valid: < pfsize=2). PrefixMap[1] has
    # ischar for 0x41 returning a Unicode codepoint.

    my @ispfx0  = (0) x 32;
    my @ischar0 = (0) x 32;
    $ispfx0[16] = 1;    # byte 0x80 is prefix

    my @ispfx1  = (0) x 32;
    my @ischar1 = (0) x 32;
    $ischar1[8] = 2;    # byte 0x41 is character

    my @firstmap = (0) x 256;
    $firstmap[0x80] = unpack("N", pack("N", -2));

    my $enc_data = build_enc(
        name     => "GOODPFX",
        pfsize   => 2,
        bmsize   => 512,
        firstmap => \@firstmap,
        prefixes => [
            {
                min        => 0x80,
                len        => 1,
                bmap_start => 0,
                ispfx      => pack("C32", @ispfx0),
                ischar     => pack("C32", @ischar0),
            },
            {
                min        => 0x40,
                len        => 2,
                bmap_start => 256,
                ispfx      => pack("C32", @ispfx1),
                ischar     => pack("C32", @ischar1),
            },
        ],
        bytemap  => [ 1, (0) x 255, 0, 0x4E00, (0) x 254 ],
    );

    my $tmpdir = File::Temp->newdir();
    my $file = write_enc($tmpdir, 'goodpfx.enc', $enc_data);

    my $name = eval { XML::Parser::Expat::load_encoding($file) };
    ok(!$@, 'valid bytemap prefix indices are accepted')
        or diag("Error: $@");
}

# ---------------------------------------------------------------
# Test 3: curdir is not in @Encoding_Path
# (prevents loading .enc from untrusted working directories)
# ---------------------------------------------------------------
{
    my $curdir = File::Spec->curdir;
    my @matches = grep { $_ eq $curdir } @XML::Parser::Expat::Encoding_Path;
    is(scalar @matches, 0,
       'File::Spec->curdir is not in @Encoding_Path');
}

done_testing;

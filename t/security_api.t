# Test expat security API wrappers (GH #102):
#   - XML_SetBillionLaughsAttackProtectionMaximumAmplification
#   - XML_SetBillionLaughsAttackProtectionActivationThreshold
#   - XML_SetReparseDeferralEnabled
#   - XML_SetAllocTrackerMaximumAmplification
#   - XML_SetAllocTrackerActivationThreshold

use Test::More;
use XML::Parser;
use XML::Parser::Expat;

# Feature-detection flags
my $have_bl    = XML::Parser::Expat::HaveBillionLaughsApi();
my $have_rd    = XML::Parser::Expat::HaveReparseDeferralApi();
my $have_at    = XML::Parser::Expat::HaveAllocTrackerApi();

diag "expat BillionLaughs API available: $have_bl";
diag "expat ReparseDeferral API available: $have_rd";
diag "expat AllocTracker API available: $have_at";

plan tests => 13;

# ---- Feature-detection helpers return 0 or 1 ----
ok( defined $have_bl, 'HaveBillionLaughsApi returns a value' );
ok( defined $have_rd, 'HaveReparseDeferralApi returns a value' );
ok( defined $have_at, 'HaveAllocTrackerApi returns a value' );

# ---- BillionLaughs API ----
SKIP: {
    skip 'BillionLaughs API not available (expat < 2.4.0)', 3
      unless $have_bl;

    my $p = XML::Parser::Expat->new;

    my $ret;
    $ret = $p->set_billion_laughs_attack_protection_maximum_amplification(100.0);
    ok( defined $ret, 'set_billion_laughs_attack_protection_maximum_amplification callable' );

    $ret = $p->set_billion_laughs_attack_protection_activation_threshold(8388608);
    ok( defined $ret, 'set_billion_laughs_attack_protection_activation_threshold callable' );

    # Verify parser still works after setting thresholds
    eval { $p->parse('<root/>') };
    is( $@, '', 'parser works after setting BillionLaughs thresholds' );

    $p->release;
}

# ---- ReparseDeferral API ----
SKIP: {
    skip 'ReparseDeferral API not available (expat < 2.6.0)', 2
      unless $have_rd;

    my $p = XML::Parser::Expat->new;

    my $ret = $p->set_reparse_deferral_enabled(0);
    is( $ret, 1, 'set_reparse_deferral_enabled(0) returns true' );

    $ret = $p->set_reparse_deferral_enabled(1);
    is( $ret, 1, 'set_reparse_deferral_enabled(1) returns true' );

    $p->release;
}

# ---- AllocTracker API ----
SKIP: {
    skip 'AllocTracker API not available (expat < 2.7.2)', 3
      unless $have_at;

    my $p = XML::Parser::Expat->new;

    my $ret;
    $ret = $p->set_alloc_tracker_maximum_amplification(100.0);
    ok( defined $ret, 'set_alloc_tracker_maximum_amplification callable' );

    $ret = $p->set_alloc_tracker_activation_threshold(8388608);
    ok( defined $ret, 'set_alloc_tracker_activation_threshold callable' );

    eval { $p->parse('<root/>') };
    is( $@, '', 'parser works after setting AllocTracker thresholds' );

    $p->release;
}

# ---- Unavailable API croaks gracefully ----
SKIP: {
    skip 'BillionLaughs API is available, cannot test croak', 1
      if $have_bl;

    my $p = XML::Parser::Expat->new;
    eval { $p->set_billion_laughs_attack_protection_activation_threshold(100) };
    like( $@, qr/not available/, 'croak when BillionLaughs API unavailable' );
    $p->release;
}

SKIP: {
    skip 'ReparseDeferral API is available, cannot test croak', 1
      if $have_rd;

    my $p = XML::Parser::Expat->new;
    eval { $p->set_reparse_deferral_enabled(0) };
    like( $@, qr/not available/, 'croak when ReparseDeferral API unavailable' );
    $p->release;
}

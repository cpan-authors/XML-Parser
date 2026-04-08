use strict;
use warnings;

on 'configure' => sub {
    requires 'File::ShareDir::Install' => '0.06';
};

requires 'File::ShareDir' => 0;
requires 'LWP::UserAgent' => 0;

# Install these for downstream testing.
if( $] > 5.030) {
    requires 'XML::XPath' => 0;
    requires 'XML::XPathEngine' => 0;
    requires 'Tie::IxHash' => 0;
}

on 'test' => sub {
    requires 'Test::More' => 0;
};

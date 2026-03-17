use strict;
use warnings;

on 'configure' => sub {
    requires 'File::ShareDir::Install' => '0.06';
};

requires 'File::ShareDir' => 0;
recommends 'LWP::UserAgent' => 0;

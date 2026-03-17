use strict;
use warnings;

on 'configure' => sub {
    requires 'File::ShareDir::Install' => '0.06';
};

requires 'File::ShareDir' => 0;
requires 'LWP::UserAgent' => 0;

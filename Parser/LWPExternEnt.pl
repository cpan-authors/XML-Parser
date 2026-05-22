# LWPExternEnt.pl
#
# Copyright (c) 2000 Clark Cooper
# All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package XML::Parser;

use strict;

use URI;
use URI::file;
use LWP::UserAgent;

my %_ALLOWED_SCHEMES = map { $_ => 1 } qw(file http https);

my @_PRIVATE_IPV4 = (
    [0x0A000000, 0xFF000000],  # 10.0.0.0/8
    [0xAC100000, 0xFFF00000],  # 172.16.0.0/12
    [0xC0A80000, 0xFFFF0000],  # 192.168.0.0/16
    [0xA9FE0000, 0xFFFF0000],  # 169.254.0.0/16
    [0x7F000000, 0xFF000000],  # 127.0.0.0/8
    [0x00000000, 0xFF000000],  # 0.0.0.0/8
);

sub _is_private_ip {
    my ($host) = @_;

    # IPv6 loopback
    if ($host =~ /^\[?::1\]?$/) {
        return 1;
    }

    # IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1)
    if ($host =~ /^\[?::ffff:(\d+\.\d+\.\d+\.\d+)\]?$/i) {
        $host = $1;
    }

    # IPv6 addresses other than loopback and mapped — allow for now
    if ($host =~ /:/) {
        return 0;
    }

    # Strip brackets
    $host =~ s/^\[|\]$//g;

    # Parse IPv4
    if ($host =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
        my $ip = ($1 << 24) | ($2 << 16) | ($3 << 8) | $4;
        for my $range (@_PRIVATE_IPV4) {
            return 1 if ($ip & $range->[1]) == $range->[0];
        }
    }

    return 0;
}

sub lwp_ext_ent_handler {
  my ($xp, $base, $sys) = @_;  # We don't use public id

  my $uri;

  if (defined $base) {
    my $base_uri = URI->new($base);
    unless (defined $base_uri->scheme) {
      $base_uri = URI->new_abs($base_uri, URI::file->cwd);
    }

    $uri = URI->new_abs($sys, $base_uri);
  }
  else {
    $uri = URI->new($sys);
    unless (defined $uri->scheme) {
      $uri = URI->new_abs($uri, URI::file->cwd);
    }
  }

  my $scheme = lc($uri->scheme || '');

  # Scheme whitelist: only file, http, https permitted
  unless ($_ALLOWED_SCHEMES{$scheme}) {
    $xp->{ErrorMessage} .= "\nURI scheme '$scheme' is not permitted"
      . " (allowed: file, http, https): $uri";
    return undef;
  }

  # For file:// URIs, delegate to the file handler path
  if ($scheme eq 'file') {
    my $path = $uri->file;
    $xp->{_BaseStack} ||= [];
    push(@{$xp->{_BaseStack}}, $base);
    $xp->base($uri);

    require IO::File;
    my $fh = IO::File->new($path, '<');
    unless (defined $fh) {
      $xp->{ErrorMessage} .= "\nFailed to open $path:\n$!";
      return undef;
    }
    return $fh;
  }

  # NoNetwork: block http/https requests
  if ($xp->{NoNetwork}) {
    $xp->{ErrorMessage} .= "\nNetwork requests disabled (NoNetwork option set): $uri";
    return undef;
  }

  # Private IP / SSRF blocking for network requests
  my $host = $uri->host || '';
  if (_is_private_ip($host)) {
    $xp->{ErrorMessage} .= "\nRequest to private/reserved IP address blocked: $uri";
    return undef;
  }

  my $ua = $xp->{_lwpagent};
  unless (defined $ua) {
    $ua = $xp->{_lwpagent} = LWP::UserAgent->new();
    $ua->env_proxy();
  }

  my $req = HTTP::Request->new('GET', $uri);

  my $res = $ua->request($req);
  if ($res->is_error) {
    $xp->{ErrorMessage} .= "\n" . $res->status_line . " $uri";
    return undef;
  }

  $xp->{_BaseStack} ||= [];
  push(@{$xp->{_BaseStack}}, $base);

  $xp->base($uri);

  return $res->content;
}  # End lwp_ext_ent_handler

sub lwp_ext_ent_cleanup {
  my ($xp) = @_;

  $xp->base(pop(@{$xp->{_BaseStack}}));
}  # End lwp_ext_ent_cleanup

1;

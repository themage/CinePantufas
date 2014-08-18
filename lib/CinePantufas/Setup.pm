package CinePantufas::Setup;

use strict;
use warnings;

use Config::Tiny;

my $CONFIG;

my $basedir = $> == 0 
    ? '/var/cinepantufas'
    : $ENV{HOME}.'/.cinepantufas';

my $defaultcfg = $> == 0
    ? '/etc/cinepantufas.cfg'
    : $basedir.'/cinepantufas.cfg';

my %defaults = (
    datadir   => "$basedir/data",
    cachedir  => "$basedir/cache",
  );

sub load {
  my $class = shift;
  my $fname = shift || $defaultcfg;

  my $cfg = {};
  if ($fname and -f $fname) {
    $cfg = Config::Tiny->read($fname);
    if (!$cfg and my $err = Config::Tiny->errstr) {
      die "error reading config '$fname': $err\n";
    }
  }

  for my $k (keys %defaults) {
    $cfg->{_}->{$k} //= $defaults{$k};
  }

  $CONFIG = bless { __cfg => $cfg}, $class;
}

sub config {
  my $class = shift;
  my $self = $CONFIG;
  my ($sec,$key) = @_;
  $sec = '_' if !$sec and $key;

  my %sec = $sec
    ? %{ $self->{__cfg}->{$sec} || {} }
    : %{ $self->{__cfg} };

  if ($key) {
    return $sec{$key};
  }

  return wantarray ? %sec : \%sec;
}

sub dump {
  print STDERR "$defaultcfg\n\n";

  my $conf = $CONFIG->{__cfg};

  for my $k (keys %{$conf->{_}}) {
    print STDERR "$k = $conf->{_}->{$k}\n";
  }
  print STDERR "\n";
 
  for my $sec (keys %$conf) {
    next if $sec eq '_';
    print STDERR "[$sec]\n";
    for my $k (keys %{$conf->{$sec}}){
      print STDERR "$k = $conf->{$sec}->{$k}\n";
    }
    print STDERR "\n";
  }

}

1;

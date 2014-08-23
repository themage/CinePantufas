package CinePantufas::Priority;

use base qw(Exporter);

use CinePantufas::Setup;

our @EXPORT_OK = qw(
  priority
);

# using the defaults means getting the lower resolutions
# but way smaller files - faster to download
my %defaults   = (
  HDTV    => 1,
  LOL     => 1,
  '720p'  => -2,
  x264    => 1,
  mkv     => -1,
  mp4     => 1,
  avi     => 1,
);
my %priorities = (
);
my $priore;

sub priority {
  my $fname = shift;

  unless (keys %priorities) {
    load_priorities();
  }

  return 0 unless keys %priorities;
  unless ($priore) {
    $priore = join '|', keys %priorities;
    $priore = qr{($priore)}i;
  }

  my @priobits = $fname =~ m{$priore}g;
  my $priority = 0;
  $priority += $priorities{ $_ } || 0
    for @priobits;

  print STDERR "PRIO: $fname => $priority\n";
  return $priority;
}

sub load_priorities {
  unless (keys %priorities) {
    %priorities = CinePantufas::Setup->config('priorities');

    unless (keys %priorities) {
      %priorities = %defaults;
    }
  }

  return unless defined wantarray;
  return wantarray ? %priorities : \%priorities;
}

1;


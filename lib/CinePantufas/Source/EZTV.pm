package CinePantufas::Source::EZTV;

use strict;
use warnings;

use CinePantufas::Core;
use CinePantufas::Priority qw(priority);

use HTTP::Tiny;
use HTTP::CookieJar;

my $prio = qr{HDTV|LOL|720p|x264|mkv|mp4|avi};
my %prio = (
  HDTV    => 1,
  LOL     => 1,
  '720p'  => -2,
  x264    => 1,
  mkv     => -1,
  mp4     => 1,
  avi     => 1,
);

my $ua;

my $base = 'https://eztv.ch';

sub _ua {
  return $ua ||= HTTP::Tiny->new(
      cookie_jar  => HTTP::CookieJar->new(),
    );
}

sub source_name { "eztv" }

sub import {
  CinePantufas::Core->register_hooks(
    get_show_list => \&retrieve_show_list,
  );
}

sub retrieve_show_list {
  my $class = shift;

  my $resp = _ua->get($base);

  die "Failed: $resp->{status} $resp->{reason}\n"
    unless $resp->{success};

  my $html = $resp->{content} ||'';

  ($html) = $html =~ m{<select\sname="SearchString">(.*?)</select>}smx;

  my %shows = $html =~ m{<option value="(\d+)">([^<]+)</option}g;

  my @shows = map {
      { name      => $shows{$_},
        params    => {
          SearchString  => $_,
        },
      }
    } keys %shows;

  return @shows;
}

sub get_episode_list {
  my ($class,$show) = @_;

  my $resp = _ua->post_form("$base/search/",
        $show->{params}
    );

  unless ($resp->{success}) {
    print STDERR "ERROR: $resp->{status} $resp->{reason}\n";
    return;
  }

  my @rows = $resp->{content} =~ m{<tr \s+ name="hover"[^>]+>(.*?)</tr>}smxg;

  my %episodes = ();
  for my $row (@rows) {
    my ($name) = $row =~ m{class="epinfo">([^>]+)</a>}smxi;
    my ($ses,$epi) = $name =~ m{S?(\d+)[Ex](\d+)}i;
    my %links = reverse
        $row=~m{<a \s href="([^"]+)" \s+ class="download_(\d+)"}smxgi;

    unless ($ses and $epi) {
      print STDERR "Missing ses and epi in '$name'\n" if $ENV{DEBUG};
      next;
    }

    $_ = "https:$_" for grep { substr($_,0,1) eq '/' } values %links;
  
    my $episode=($ses+0).'x'.sprintf('%02d', $epi);
    my $rowprio = priority($name);
    
    if (!$episodes{$episode} or $rowprio > $episodes{$episode}->{prio} ) {
      $episodes{$episode} = {
          filename  => $name,
          prio      => $rowprio,
          torrents  => [values %links],
          season    => $ses,
          episode   => $epi,
          number    => $episode,
        };
    }
  }

  return values %episodes;
}

1;

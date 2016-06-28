package CinePantufas::Client::Transmission;

use strict;
use warnings;

use CinePantufas::Core;
use CinePantufas::Setup;

use HTTP::Tiny;
use JSON qw(to_json from_json);

my $session;
my $sesstime=0;

my %ok_res = map {$_ => 1} (
  'success',
  'duplicate torrent',
);

sub import {
  my $config = CinePantufas::Setup->config('transmission');

  if ($config and $config->{api_url}) {
    CinePantufas::Core->register_hooks(
      add_torrent           => \&add_torrent,
      list_running_torrents => \&list_torrents,
    );
  }
}

sub add_torrent {
  my $class = shift;
  my $link  = shift;
  my $retry = shift // 3;

  my $config = CinePantufas::Setup->config('transmission');
  my $url = $config->{api_url};

  my $ua = HTTP::Tiny->new(timeout => 180);

  unless ($session and $sesstime>(time-60) ) {
    my $resp = $ua->get($url);

    if ($resp->{headers}->{'x-transmission-session-id'}) {
      $session = $resp->{headers}->{'x-transmission-session-id'};
      $sesstime = time;
    }
  }

  my $content = to_json({
      method    => 'torrent-add',
      arguments => {
        filename  => $link,
      }
    }, {utf8=>1});

  my $resp = $ua->post(
      $url,{
      headers => {
        "X-Transmission-Session-Id" => $session,
      },
      content => $content,
    });

  if ($resp->{status} == 200) {
    my $res = from_json($resp->{content});
    if ($ok_res{ $res->{result} } ) {

      # TODO(nsenica): Validate if seed_ratio is double
      if ( $config->{seed_ratio} ) {
            my $content = to_json({
                method    => 'torrent-set',
                arguments => {
                  ids  => [$res->{arguments}->{'torrent-added'}->{hashString}],
                  seedRatioLimit => $config->{seed_ratio},
		  seedRatioMode  => 1, # 0 = Global , 1 = Torrent mode, 2 = Unlimited
                }
              }, {utf8=>1});

            $ua->post(
                $url,{
                headers => {
                  "X-Transmission-Session-Id" => $session,
                },
                content => $content,
              });
      }

      return {
        status => 'ok',
        hashString => $res->{arguments}->{'torrent-added'}->{hashString}
                    ||'',
      };
    }
  } elsif ( $resp->{status} == 409 and $retry--) {
    $session = undef;
    return $class->add_torrent( $link, $retry );
  } elsif ( $resp->{status} == 599 ) {
    if ($ENV{DEBUG}) {
      print STDERR "got a 599: $url => $content\n+++++++++\n$resp->{content}\n\n"; 
    }
  } else {
    my $more = $ENV{DEBUG} ? ($resp->{content}."\n") : '';
    warn "error on transmission: $resp->{status} $resp->{reason}\n$more";
  }

  return 0;
}

sub list_torrents {
  my $class = shift;

  my $config = CinePantufas::Setup->config('transmission');
  my $url = $config->{api_url};

  my $ua = HTTP::Tiny->new();

  unless ($session) {
    my $resp = $ua->get($url);

    if ($resp->{headers}->{'x-transmission-session-id'}) {
      $session = $resp->{headers}->{'x-transmission-session-id'};
    }
  }

  my $content = to_json({
      method    => 'torrent-get',
      arguments => {
        fields  => [qw(
            id
            hashString
            isFinished
            downloadDir
            files
          )],
      }
    }, {utf8=>1});

  my $resp = $ua->post(
    $url,{
      headers => {
        "X-Transmission-Session-Id" => $session,
      },
      content => $content,
    }
  );
 
  if ($resp->{success}) {
    my $res = from_json($resp->{content}, {utf8=>1});
    return unless $ok_res{ $res->{result} };

    my @torrents = @{ $res->{arguments}->{torrents} };

    return \@torrents;
  } else {
    my $more = $ENV{DEBUG} ? $resp->{content} : '';
    die "error on transmission: $resp->{status} $resp->{reason}\n$more\n";
  }
}

sub remove_torrent {
  my $class = shift;
  my $tor   = shift;

  my $config = CinePantufas::Setup->config('transmission');
  my $url = $config->{api_url};

  my $ua = HTTP::Tiny->new(timeout => 120);

  unless ($session) {
    my $resp = $ua->get($url);

    if ($resp->{headers}->{'x-transmission-session-id'}) {
      $session = $resp->{headers}->{'x-transmission-session-id'};
    }
  }

  my $content = to_json({
      method    => 'torrent-remove',
      arguments => {
        ids   => [ $tor->{id} ],
        'delete-local-data' => $config->{delete_local_data} ? JSON::true : JSON::false,
      }
    }, {utf8=>1});

  my $resp = $ua->post(
    $url,{
      headers => {
        "X-Transmission-Session-Id" => $session,
      },
      content => $content,
    }
  );
 
  if ($resp->{success}) {
    my $res = from_json($resp->{content}, {utf8=>1});
    return $ok_res{ $res->{result} } || 0;
  } else {
    die "error on transmission: $resp->{status} $resp->{reason}\n";
  }

}

1;

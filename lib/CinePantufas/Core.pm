package CinePantufas::Core;

use strict;
use warnings;

use CinePantufas::Setup;
use File::Copy qw(copy);

use DB_File;
use JSON qw(to_json from_json);

my %hooks;

sub main {
  my $class = shift;
  my ($cmd,@args) = @_;

  $cmd = 'help' unless $cmd;
  $cmd =~ s{-}{_}g;

  $class->_check_dirs;

  my @res = ();
  if (my $handler = $class->can("__cmd_$cmd")) {
    push @res, $handler->($class,@args);
  } elsif ( $hooks{$cmd} ) {
    for my $hook ( @{ $hooks{ $cmd } }){
      my $handler = $hook->{handler};
      my $cls   = $hook->{class};
      push @res, $handler->($cls,@args);
    }
  } else {
    die "unknow command: '$cmd @args'\n";
  }

  return @res;
}

sub register_hooks {
  my $class = shift;
  my %reghooks = @_;

  my ($cls) = caller();

  for my $k (keys %reghooks) {
    $hooks{ $k } ||= [];
    push @{ $hooks{ $k } }, {class=> $cls, handler=> $reghooks{$k} };
  }

}

sub __cmd_update {
  my $class = shift;

  my ($sources, $newshows)=(0,0);
  my @to_update = ();
  for my $hook (@{ $hooks{get_show_list} }) {
    my $cls = $hook->{class};
    my $srcname = $cls->source_name;
    my $handler = $hook->{handler};
    my @list = $handler->($cls);
    push @to_update, grep {
        $_->{name},
      } map {
        { %$_,
          class   => $cls,
          source  => $srcname,
        }
      } @list;
    $sources++
      if @list;
  }

  my $fname = ___show_file();
  my %epidb;
  tie %epidb, 'DB_File', $fname;
  for my $show (@to_update) {
    my $k = $show->{name};
    $k =~s{[^\w\s\-]}{_}g;
    $k =~s{__+}{_}g;
    $k =~s{_*\s+_*}{-}g;
    $k =~s{_*\z}{};
    $k = lc($k);

    my $rec;
    if ($epidb{$k}) {
      $rec = from_json($epidb{$k});
      $rec->{sources}->{ $show->{source} } = $show;
    } else {
      $rec = { sources => {$show->{source} => $show} };
      $rec->{first_seen} = time;
      $rec->{name} = $show->{name};

      $newshows++;
    }
    $epidb{$k} = to_json($rec, {utf8=>1});
  }

  print STDERR "updated $sources source(s): $newshows new shows\n";
}


sub __cmd_all_shows {
  my $class = shift;
  my $fname = ___show_file();

  my %epidb;
  tie %epidb, 'DB_File', $fname;
  for my $sid (sort keys %epidb) {
    my $show = from_json($epidb{$sid},{utf8=>1});
    my $name = $show->{name};
    my $srcs = scalar keys %{ $show->{sources} };

    if (length($sid)>30) {
      printf " %s\n %32s %2d %s\n", $sid,'',$srcs, $name;
    } else {
      printf " %-32s %2d %s\n", $sid, $srcs, $name;
    }
  }
}
*__cmd_all = *__cmd_all_shows;

sub __cmd_search {
  my $class = shift; 
  my @regs = map { qr{$_}i } @_;
  my $fname = ___show_file();
  
  my %showdb;
  tie %showdb, 'DB_File', $fname;

  SHOW:
  for my $sid (sort keys %showdb) {
    my $show = from_json($showdb{$sid},{utf8=>1});
    my $name = $show->{name};
    for my $r (@regs) {
      next SHOW unless $name =~ $r;
    }

    my $srcs = scalar keys %{ $show->{sources} };

    if (length($sid)>30) {
      printf " %s\n %32s %2d %s\n", $sid,'',$srcs, $name;
    } else {
      printf " %-32s %2d %s\n", $sid, $srcs, $name;
    }
  }
}

sub __cmd_add_show {
  my $class = shift;
  my ($show,$episode) = @_;

  my $sname = ___show_file();
  my %showdb;
  tie %showdb, 'DB_File', $sname;

  my $fname = ___follow_file();
  my %followdb;
  tie %followdb, 'DB_File', $fname;

  if ($showdb{$show}) {
    my $srec = from_json($showdb{$show}, {utf8=>1});
    if ($followdb{$show}) {
      print STDERR "Already following $show [$srec->{name}]\n";
    } else {
      my ($seas,$epis) = (0,0);
      if ($episode) {
        if ($episode =~m{S(\d+)E(\d+)}i) {
          $seas = $1;
          $epis = $2;
        } elsif ($episode =~ m{(\d+)x(\d+)}i) {
          $seas = $1;
          $epis = $2;
        }
      }

      $followdb{$show} = to_json({
          sid   => $show,
          since => time,
          first_season  => $seas,
          first_episode => $epis,
        },{utf8=>1});
    }
  } else {
    die "$show is missing - try update/search\n";
  }
}
*__cmd_add = *__cmd_add_show;

sub __cmd_del_show {
  my $class = shift;
  my $show  = shift;

  my $sname = ___show_file();
  my %showdb;
  tie %showdb, 'DB_File', $sname;

  my $fname = ___follow_file();
  my %followdb;
  tie %followdb, 'DB_File', $fname;

  if ($followdb{$show}) {
    my $info = from_json($showdb{$show}, {utf8=>1});
    my $follow  = from_json($followdb{$show},{utf8=>1});
    if ($info) {
      my $date=join"-", (localtime($follow->{since}))[5,4,3];

      printf "%s\nshowid: %s\nfollowed since: %s - from %dx%d\n%s\n",
        $info->{name}, $show,
        $follow->{since},
        $follow->{first_season},
        $follow->{first_episode},
        '-'x70;
      print "\n => stopped following\n";

      delete $followdb{$show};
    }
  } else {
    print STDERR "You are not following '$show'\n";
  }
}
*__cmd_del = *__cmd_del_show;

sub __cmd_list {
  my $class = shift;
  
  my $sname = ___show_file();
  my %showdb;
  tie %showdb, 'DB_File', $sname;

  my $fname = ___follow_file();
  my %followdb;
  tie %followdb, 'DB_File', $fname;

  for my $show (keys %followdb) {
    my $info    = from_json($showdb{$show},{utf8=>1});
    my $follow  = from_json($followdb{$show},{utf8=>1});
    
    unless ($info) {
      print STDERR "missing info for $show\n";
      next;
    }

    my $date=join"-", (localtime($follow->{since}))[5,4,3];
    printf "%s\nshowid: %s\nfollowed since: %s - from %dx%d\n%s\n",
        $info->{name}, $show,
        $follow->{since},
        $follow->{first_season},
        $follow->{first_episode},
        '-'x70;
  }
}

sub __cmd_get_new {
  my $class = shift;

  my $sname = ___show_file();
  my %showdb;
  tie %showdb, 'DB_File', $sname;

  my $fname = ___follow_file();
  my %followdb;
  tie %followdb, 'DB_File', $fname;

  my $ename = ___episode_file();
  my %epidb;
  tie %epidb, 'DB_File', $ename;

  my $total = 0;
  for my $show (keys %followdb) {
    my $new = 0;
    my $info      = from_json($showdb{$show},{utf8=>1});
    my $follow    = from_json($followdb{$show},{utf8=>1});
    
    for my $source (values %{ $info->{sources} }) {
      my $class = $source->{class};

      my @episodes = $class->get_episode_list( $source );

      for my $episode (@episodes) {
        my $k = $show.';:;'.$episode->{number};
        if ($epidb{$k}) {
          my $old = from_json($epidb{$k},{utf8=>1});
          next unless $episode->{is_prio} and !$old->{is_prio};
        }

        my $status = 'new';
        $status = 'skipped'
          if $episode->{season} < $follow->{first_season}
            or ($episode->{season} == $follow->{first_season}
              and $episode->{episode} < $follow->{first_episode}
            );
        my $info = {
            %$episode,
            first_seen  => time,
            status      => $status,
            show        => $show,
          };

        $epidb{$k} = to_json($info, {utf8=>1});
        $new++ if $status eq 'new';
      }
    }
    print STDERR "$info->{name}: $new new episodes\n"
      if $new;
    $total += $new;
  }

  print STDERR "Total: $total new episodes\n"
    if $total;

  untie %showdb;
  untie %followdb;
  untie %epidb;

  $class->__queue_new();
}
*__cmd_new = *__cmd_get_new;

sub __queue_new {
  my $class = shift;

  my $ename = ___episode_file();
  my %epidb;
  tie %epidb, 'DB_File', $ename;

  my $queued = 0;
  EPISODE:
  for my $k (sort keys %epidb) {
    my $episode = from_json($epidb{$k}, {utf8=>1});
    next unless $episode->{status} eq 'new';

    my $link = ${$episode->{torrents}}[
        rand(scalar @{$episode->{torrents}})
      ];

    for my $hook (@{ $hooks{add_torrent}||[] }) {
      my $cls = $hook->{class};
      my $handler = $hook->{handler};
      my $res = $handler->($cls, $link);

      if ( $res and $res->{status} eq 'ok') {
        $episode->{status} = 'queued';
        $episode->{hashString} = $res->{hashString}
          if $res->{hashString};
        $epidb{$k} = to_json($episode,{utf8=>1});
        $queued++;

        next EPISODE;
      }
    }
  }

  print STDERR "Queued $queued new episodes\n"
    if $queued;
}

sub __cmd_reget {
  my $class = shift;
  my ($show,$episode) = @_;

  die "Missing show or episode\n"
    unless $show and $episode;

  my $fname = ___follow_file();
  my %followdb;
  tie %followdb, 'DB_File', $fname;

  my $ename = ___episode_file();
  my %epidb;
  tie %epidb, 'DB_File', $ename;

  unless ($followdb{ $show }) {
    die "You're not following '$show'";
  }

  my ($seas,$epi) = $episode =~ m{S?(\d+)[Ex](\d+)}i;
  $episode = ($seas+0).'x'.sprintf('%02d', $epi);
  my $k = $show.';:;'.$episode;
  if ($epidb{ $k }) {
    my $info = from_json($epidb{$k}, {utf8=>1});
    $info->{status} = 'new';
    $epidb{$k} = to_json($info);

    print STDERR "set to new $show - $episode\n";
  } else {
    die "Unknow episode $show - $episode\n";
  }

  untie %epidb;
  untie %followdb;
  $class->__queue_new();
}

sub __cmd_move_done {
  my $class = shift;

  my $ename = ___episode_file();
  my %epidb;
  tie %epidb, 'DB_File', $ename;

  HOOK:
  for my $hook (@{ $hooks{list_running_torrents}||[] }) {
    my $cls = $hook->{class};
    my $handler = $hook->{handler};

    print STDERR "calling hook in $cls\n";
    my $res = $handler->($cls);
    if ($res and ref $res eq 'ARRAY') {
      my %torrents = map { $_->{hashString} => $_ } 
          grep { $_->{isFinished} } @$res;

      next HOOK unless keys %torrents;

      for my $k (keys %epidb) {
        my $info = from_json($epidb{$k}, {utf8=>1});
        next unless $info->{status} eq 'queued';
        next unless my $tor = $torrents{ $info->{hashString} };

        if (__copy_files( $info => $tor )) {
          if ($cls->remove_torrent($tor) ) {
            $info->{status} = 'done';
            $epidb{$k} = to_json( $info, {utf8=>1});

            print STDERR "$info->{show} - $info->{number} ready\n";
            exit; #only remove 1
          }
        }
      }
    }
  }
}
*__cmd_done = *__cmd_move_done;

sub __copy_files {
  my ($info, $tor) = @_;
  my $config = CinePantufas::Setup->config('move');

  return unless $config->{basedir};

  my $source = $tor->{downloadDir};
  my $fname  = __find_best_file( @{ $tor->{files} } );

  return unless $fname;

  my $ext = (split /\./, $fname)[-1];

  $source .= '/' unless substr($source,-1) eq '/';
  $source .= $fname;

  my $dest = $config->{basedir};
  $dest .= '/' unless substr($dest,-1) eq '/';
  $dest .= $info->{show}.'/';
  mkdir $dest unless -d $dest;

  $dest .= 'Season'.$info->{season}.'/';
  mkdir $dest unless -d $dest;

  die "error creating directory $dest\n" unless -d $dest;

  $dest .= $info->{show}.'--'.$info->{number}.'.'.$ext;

  if ($config->{disabled}) {
    print STDERR "would move '$source' to '$dest'\n";
    return 0;
  } else {
    copy($source, $dest) or die "Copy failed: $!\n";
    return 1;
  }
}

my %good_types = map {$_ => 1} qw(
  mp4
  avi
  mkv
);
sub __find_best_file {
  my @files = @_;

  my ($file) = grep {
      my $ext = (split /\./, $_)[-1];
      $good_types{$ext};
    } map {
      $_->{name}
    } sort {
      $b->{length} <=> $a->{length}
    } @files;

  return $file ? $file : ();
}

my @helps = qw(
  update
  get_new
  list
  all_shows
  search
  add_show
  del_show
  reget
  move_done
);
my %help = (
  update    => 'update the list of known shows',
  get_new   => "update the list of episodes for the followed shows\n".
               "\t\tand queue the new ones",
  list      => 'list the followed shows',
  all_shows => 'list all known shows',
  search    => 'search for shows by keywork',
  add_show  => 'add a show to the followed list - first episode optional',
  del_show  => 'delete a show from the followed list',
  reget     => 'get a specific episode again',
  move_done => 'move the files that are complete to the final folder',
);

my %howto = (
  update    => 'update',
  get_new   => 'get-new',
  list      => 'list',
  all_shows => 'all-shows',
  search    => 'search castle',
  add_show  => 'add-show castle S05E07',
  del_show  => 'del-show castle',
  reget     => 'reget castle 06x09',
  move_done => 'move-done',
);

my %params = (
  search    => '<keyword> [<keyword>]*',
  add_show  => '<show-name> [<first-episode>]',
  del_show  => '<show-name>',
  reget     => '<show-name> <episode>',
);
sub __cmd_help {
  my ($class, $cmd) = @_;

  if ( $cmd and $help{$cmd} ) {
    my $params = $params{$cmd} || '';
    my $help  = $help{$cmd} || '';
    my $howto = $howto{$cmd} || '';
    print STDERR "$0 $cmd $params\n\n",
      "\t$help\n\n\tUsage:\n\t\t$0 $howto\n\n";
  } else {
    print STDERR "$0 <command>\n  Accepts commands:\n\n";
    for my $cmd (@helps) {
      my $help  = $help{$cmd} || '';
      print STDERR sprintf "   %-12s %s\n",$cmd, $help; 
    }
  }
  print STDERR "\nNote: <episode> can be <S00E00> or 00x00\n\n";

  return;
}

sub __cmd_dump_config {
  CinePantufas::Setup->dump();
}


sub _check_dirs {
  my $class = shift;

  my $datadir   = CinePantufas::Setup->config('','datadir');
  my $cachedir  = CinePantufas::Setup->config('','cachedir');

  __makedir( $datadir );
  __makedir( $cachedir );
}

sub __makedir {
  my $dir = shift;

  die "hien? '$dir'" unless $dir; 
  return if -d $dir;
  my ($parent) = $dir =~ m{(.*)/[^/]+/?\z};

  if (!-d $parent) {
    __makedir( $parent );
  }

  mkdir $dir
    or die "Error creating '$dir': $!\n";
}

sub ___show_file {
  my $fname = CinePantufas::Setup->config('','datadir');
  $fname .= '/' unless substr($fname,-1) eq '/';
  $fname .= 'shows.db';

  return $fname;
}

sub ___follow_file {
  my $fname = CinePantufas::Setup->config('','datadir');
  $fname .= '/' unless substr($fname,-1) eq '/';
  $fname .= 'follow.db';

  return $fname;
}

sub ___episode_file {
  my $fname = CinePantufas::Setup->config('','datadir');
  $fname  .= '/' unless substr($fname,-1) eq '/';
  $fname  .= 'episodes.db';

  return $fname;
}

sub ___show_episode_file {
  my $fname = CinePantufas::Setup->config('','datadir');
  $fname  .= '/' unless substr($fname,-1) eq '/';
  $fname  .= 'show_episodes.db';

  return $fname;
}

1;

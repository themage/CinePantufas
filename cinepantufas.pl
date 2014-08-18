#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use CinePantufas::Setup;
BEGIN {
  CinePantufas::Setup->load;
}

use CinePantufas::Core;
use CinePantufas::Source::EZTV;
use CinePantufas::Client::Transmission;

CinePantufas::Core->main(@ARGV);


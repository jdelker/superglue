#!/usr/bin/perl

use strictures 2;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More;

require_ok('Superglue::Contact');

done_testing;

exit;

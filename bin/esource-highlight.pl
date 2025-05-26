#! /usr/bin/env perl

use strict;
use warnings;
use utf8;

use pEFL;
use pEFL::Evas;

use eSourceHighlight;
my $open_file = $ARGV[0];
my $sh = eSourceHighlight->new($open_file);

$sh->init_ui();

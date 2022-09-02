#! /usr/bin/env perl

use strict;
use warnings;
use utf8;

use Efl;
use Efl::Evas;

use eSourceHighlight;

my $sh = eSourceHighlight->new();

$sh->init_ui();
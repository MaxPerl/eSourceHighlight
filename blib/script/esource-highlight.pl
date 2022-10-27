#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use pEFL;
use pEFL::Evas;

use eSourceHighlight;


my $sh = eSourceHighlight->new();

$sh->init_ui();
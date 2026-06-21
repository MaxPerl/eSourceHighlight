#! /usr/bin/env perl

use strict;
use warnings;
use utf8;
use eSourceHighlight;
use eSourceHighlight::SingleInstance qw(check_for_running_instance send_path_and_close);

my $open_file = $ARGV[0];

# Prüfen, ob bereits eine Instanz läuft: Wenn dies der Fall ist, 
# verbinden wir uns nur mit dem bestehenden Socket und 
# übergeben den Pfad
if (my $sock = check_for_running_instance()) {
    send_path_and_close($sock, $open_file);
    exit 0;
}

# Es läuft noch keine Instanz. Starte die erste und einzige Instanz von eSourceHighlight 
# Wichtig: check_for_running_instance() hat uns bisher nur per flock() das exklusive Recht gesichert, 
# die Server-Instanz werden zu dürfen Tatsächlich aufgebaut wird der Server (Socket + FdHandler) 
#aber erst in init_ui(), sobald der EFL-Mainloop bereitsteht.
my $sh = eSourceHighlight->new($open_file);
$sh->init_ui();

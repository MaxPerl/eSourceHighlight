package eSourceHighlight::SingleInstance;

# Mit Hilfe dieses Moduls wird dafür gesorgt, dass immer nur eine Instanz läuft:
#   - check_for_running_instance(): wird VOR eSourceHighlight->new() aufgerufen.
#     Klärt per Unix-Domain-Socket + Lockdatei, ob es schon eine laufende
#     Instanz gibt. Gibt entweder einen verbundenen Socket zurueck (eSourceHighlight
#     läuft schon -> Aufrufer soll send_path_and_close() aufrufen und sich
#     beenden) oder undef (es gibt noch keine Instanz -> Aufrufer soll eSourceHighlight
#     normal starten und dabei auch den Socket Server initialisieren.)
#   - send_path_and_close($sock, $path): schickt den Pfad ueber den von
#     check_for_running_instance() gelieferten Socket und schliesst ihn.
#   - start_server($on_path): Hängt einen Ecore::FdHandler an unseren Socket, der
#     eingehende Verbindungen event-getrieben abarbeitet und für jeden
#     empfangenen Pfad $on_path->($path) aufruft. Muss in init_ui aufgerufen werden
#	  (Ecore muss bereits initialisiert sein für den FDHandler!)
#
# Race-Condition-sicher: zwei quasi gleichzeitig startende Instanzen können
# sich nie beide fuer "die Server-Instanz" halten, weil der Lock exklusiv ist.

use strict;
use warnings;
use IO::Socket::UNIX;
use Fcntl qw(:flock);
use File::Spec;
use Time::HiRes qw(sleep);
use Exporter 'import';
use pEFL::Ecore;

our @EXPORT_OK = qw(check_for_running_instance send_path_and_close start_server);

my $RUNTIME_DIR = $ENV{XDG_RUNTIME_DIR} // '/tmp';
my $SOCK_PATH   = "$RUNTIME_DIR/esource-highlight.sock";
my $LOCK_PATH   = "$RUNTIME_DIR/esource-highlight.lock";

my $MAX_RACE_RETRIES = 5;
my $RACE_RETRY_DELAY = 0.1;   # Sekunden

# Modul-globale Variablen: müssen für die Lebensdauer des Prozesses am
# Leben bleiben (Lock-Filehandle hält den flock, $SERVER hält den
# listening Socket offen). Falls eine davon vom Garbage Collector
# eingesammelt wird, fällt der Lock bzw. der Socket weg.
my $LOCK_FH;
my $SERVER;
my $FD_HANDLER;


##############################################
# Check for existing Server and try to connect
##############################################

sub _connect_to_running_instance {
    return IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Peer => $SOCK_PATH,
    );
}

# --- Anmerkung zur Lock-Datei:
#
# $LOCK_PATH ist nur eine leere Datei - ihr INHALT ist voellig egal, sie
# dient nur als benannter Anknuepfungspunkt, auf den flock() einen Lock
# legen kann.
#
# Der entscheidende Punkt: ein flock()-Lock haengt am offenen Filehandle,
# NICHT an der Datei selbst. Das Betriebssystem gibt ihn automatisch frei,
# sobald der Filehandle geschlossen wird ODER der Prozess endet - egal ob
# sauber, durch Crash oder kill -9. Deswegen:
#   - Wir rufen nirgendwo explizit "unlock" auf. $LOCK_FH bleibt fuer die
#     gesamte Prozesslaufzeit offen, das OS raeumt beim Beenden garantiert
#     auf (anders als z.B. bei einer PID-Datei, wo man verwaiste Einträge
#     selbst erkennen muesste - PID-Reuse-Problem).
#   - Wir löschen die Datei nie. Beim nächsten Start liegt sie noch leer
#     auf der Platte rum, wird aber einfach erneut geöffnet; falls kein
#     Prozess mehr drauf sitzt, klappt flock() sofort.
#
# Wozu der Lock ueberhaupt? Er schließt ein schmales Zeitfenster: starten
# zwei Instanzen quasi zeitgleich, scheitern beide am connect() (noch hoert
# niemand zu) - ohne Lock würden sich beide fuer "den Server" halten und
# gleichzeitig versuchen, den Socket zu binden. Mit dem exklusiven Lock
# gewinnt garantiert nur einer; der andere merkt das (flock schlaegt fehl)
# und versucht es kurz danach erneut als Client.
#
# (Hinweis am Rande: der Socket selbst braucht dagegen aktives Cleanup -
# unlink $SOCK_PATH weiter unten - weil eine Unix-Domain-Socket-Datei,
# anders als ein Lock, NICHT automatisch verschwindet, wenn der Prozess
# stirbt. Uns interessiert beim Lock nur der Lock-Zustand, nicht die Datei.)



# Versucht, sich mit einer laufenden Instanz zu verbinden. Klappt das nicht,
# wird race-sicher per flock() versucht, die Server-Rolle zu reservieren.
#
# Rueckgabe: ein verbundener Socket  -> es läuft schon eine Instanz, der
#                                       Aufrufer soll send_path_and_close()
#                                       aufrufen und sich beenden
#            undef                   -> es läuft keine Instanz, der Aufrufer macht
#                                       normal weiter und startet dabei den Server
sub check_for_running_instance {
    for my $attempt (1 .. $MAX_RACE_RETRIES) {
        if (my $sock = _connect_to_running_instance()) {
            return $sock;
        }

        # Niemand hört zu -> versuchen, den exklusiven Server-Lock zu bekommen.
        open($LOCK_FH, '>', $LOCK_PATH)
            or die "Kann Lockdatei $LOCK_PATH nicht oeffnen: $!\n";

        if (flock($LOCK_FH, LOCK_EX | LOCK_NB)) {
            return undef;
        }
        close $LOCK_FH;

        # Echte Race Condition: jemand anderes ist GERADE dabei, Server zu
        # werden. Kurz warten, dann nächste Runde wieder von vorn (erst
        # connect versuchen, dann ggf. Lock). sleep() kommt hier von
        # Time::HiRes und kann - anders als das eingebaute sleep() -
        # Sekundenbruchteile.
        sleep($RACE_RETRY_DELAY);
    }

    die "Konnte weder Client- noch Server-Rolle uebernehmen ".
        "(Lockdatei $LOCK_PATH haengt fest?)\n";
}

# Schickt $path ueber $sock an die laufende Instanz und schließt die
# Verbindung. $sock muss von check_for_running_instance() stammen.
sub send_path_and_close {
    my ($sock, $path) = @_;
    $path = File::Spec->rel2abs($path) if defined $path;

    print $sock (defined $path ? "$path\n" : "\n");
    $sock->shutdown(1);   # "fertig mit senden" -> Gegenseite bekommt EOF
    close $sock;
}

################################################
# Init SERVER and FdHandler
################################################

sub on_readable {
	my ($data) = @_;
	my $SERVER = $data->[0];
	my $on_path = $data->[1];

	# Solange Verbindungen anstehen, alle abarbeiten (es könnten sich
    # theoretisch mehrere angesammelt haben, bevor der Handler feuert).
        while (my $client = $SERVER->accept()) {
            # Eigentlich ist $client->blocking(1) nicht erforderlich, weil der unabhängige
            # neue unabhängige $client FH schon defaultmäßig blockiert (er erbt nicht das 
            # non-blocking von $SERVER). $client->blocking(0) dient daher nur der Klarstellung!
            # Warum wollen wir einen blockierenden Client innerhalb unserer Mainloop? 
            # Ein nicht-blockierender $client könnte unerwartet undef liefern, obwohl er
            # gleich Daten schickt - einfach weil die Daten noch nicht im Kernel-Buffer angekommen sind.
            # Das verhindert nun der blockierende Client!
            #
            # Das Risiko dagegen, dass $client für immer oder auch nur längere Zeit blockiert 
            # und die UI einfriert, ist hier dagegen vernachlässigbar, weil der einzige Client 
            # unser eigenes, vertrauenswürdiges Skript ist, das über einen bereits verbundenen 
            # lokalen Unix-Socket eine einzige (!) Zeile schickt und sofort (!!!) schließt.
            # Ein Blockieren ist daher nie wirklich spürbar oder sonst gefährlich
            $client->blocking(1);
            my $line = <$client>;
            close $client;

            chomp $line if defined $line;
            $on_path->( (defined $line && length $line) ? $line : undef );
        }
        return 1;   # ECORE_CALLBACK_RENEW -- Handler aktiv halten
}

# Baut den listening Socket auf und hängt einen Ecore::FdHandler ein, der
# bei eingehenden Verbindungen sofort (event-getrieben, kein Polling)
# reagiert. $on_path wird fuer jeden empfangenen Pfad aufgerufen (mit undef,
# falls eine Instanz ohne Dateiargument gestartet wurde -> z.B. nur zum
# Fokussieren des Fensters nutzbar).
sub start_server {
    my ($on_path) = @_;

    unlink $SOCK_PATH if -e $SOCK_PATH;   # verwaiste Socket-Datei entfernen

    $SERVER = IO::Socket::UNIX->new(
        Type   => SOCK_STREAM(),
        Local  => $SOCK_PATH,
        Listen => 5,
    ) or die "Kann Socket $SOCK_PATH nicht erstellen: $!\n";

	# Der Listening-Socket ($SERVER) ist bewusst non-blocking, 
	# damit die Schleife while (my $client = $SERVER->accept()) sofort mit undef zurückkommt, 
	# statt zu hängen, wenn keine Verbindung mehr ansteht. 
	# Das ist wichtig, weil dieser Callback synchron in der EFL-Mainloop läuft – 
	# würde accept() hier blockieren, würde der ganze Editor einfrieren.
    $SERVER->blocking(0);

    $FD_HANDLER = pEFL::Ecore::FdHandler->add(
        $SERVER->fileno(),
        ECORE_FD_READ,
        \&on_readable,
        [$SERVER, $on_path],
    );

    return;
}

1;

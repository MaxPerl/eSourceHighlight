package eSourceHighlight::Settings;

use 5.006001;
use strict;
use warnings;
use utf8;

require Exporter;

use pEFL::Elm;
use pEFL::Evas;

use YAML('Load', 'Dump');
use File::HomeDir;
use File::Path ('make_path');

our @ISA = qw(Exporter);

our $AUTOLOAD;

sub new {
	my ($class, $app, %opts) = @_;
	
	# Get index
	
	my $obj = {
		app => $app,
		elm_tabspinner => undef,
		elm_unexpand_check => undef,
		elm_expand_check => undef,
		elm_settings_win => undef,
		};
	bless($obj,$class);
	
	return $obj;
}

sub show_dialog {
	my ($self,$app) = @_;
	
	my $config = $self->load_config();
	
	my $settings_win = pEFL::Elm::Win->add($app->elm_mainwindow(), "Settings", ELM_WIN_BASIC);
	$settings_win->title_set("Settings");
	my $bg = pEFL::Elm::Bg->add($settings_win);
	$bg->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$settings_win->resize_object_add($bg);
	$bg->show();
	$settings_win->focus_highlight_enabled_set(1);
	$settings_win->autodel_set(1);
	
	my $bx = pEFL::Elm::Box->add($settings_win);
	$bx->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$bx->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$bx->padding_set(10,10);
	$bx->show();
	
	my $header = pEFL::Elm::Label->add($bx);
	$header->text_set("<b>Open file options</b>");
	$header->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$header->size_hint_align_set(0.05,0);
	$header->show(); $bx->pack_end($header);
	
	my $bx2 = pEFL::Elm::Box->add($bx);
	$bx2->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$bx2->size_hint_align_set(EVAS_HINT_FILL, 0);
	$bx2->padding_set(10,0);
	$bx2->horizontal_set(1);
	$bx2->show(); $bx->pack_end($bx2);
	
	my $tabs_label = pEFL::Elm::Label->new($bx2);
	$tabs_label->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$tabs_label->size_hint_align_set(0.1,EVAS_HINT_FILL);
	$tabs_label->text_set("Tabstops");
	$tabs_label->show(); $bx2->pack_end($tabs_label);
	
	my $tabs_spinner = pEFL::Elm::Spinner->add($bx2);
	$tabs_spinner->value_set($config->{tabstops} || 4);
	$tabs_spinner->size_hint_align_set(EVAS_HINT_FILL,0.5);
	$tabs_spinner->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$tabs_spinner->show(); $bx2->pack_end($tabs_spinner);
	
	my $unexpand_check = pEFL::Elm::Check->add($bx);
	$unexpand_check->size_hint_align_set(0,EVAS_HINT_FILL);
	$unexpand_check->text_set("Unexpand white space to tabs");
	$unexpand_check->state_set(1) if ($config->{unexpand});
	$unexpand_check->show(); $bx->pack_end($unexpand_check);
	
	my $expand_check = pEFL::Elm::Check->add($bx);
	$expand_check->size_hint_align_set(0,EVAS_HINT_FILL);
	$expand_check->text_set("Expand tabs to white space");
	$expand_check->state_set(1) if ($config->{expand});
	$expand_check->show(); $bx->pack_end($expand_check);
	
	
	my $btn_bx = pEFL::Elm::Box->add($bx);
	$btn_bx->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$btn_bx->size_hint_align_set(EVAS_HINT_FILL, 0);
	$btn_bx->horizontal_set(1);
	$btn_bx->show(); $bx->pack_end($btn_bx);
	
	my $ok_btn = pEFL::Elm::Button->new($btn_bx);
	$ok_btn->text_set("OK");
	$ok_btn->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$ok_btn->size_hint_align_set(EVAS_HINT_FILL, EVAS_HINT_FILL);
	$ok_btn->show(); $btn_bx->pack_end($ok_btn);
	
	my $cancel_btn = pEFL::Elm::Button->new($btn_bx);
	$cancel_btn->text_set("Cancel");
	$cancel_btn->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$cancel_btn->size_hint_align_set(EVAS_HINT_FILL, EVAS_HINT_FILL);
	$cancel_btn->show(); $btn_bx->pack_end($cancel_btn);
	
	# Save important widgets
	$self->elm_tabs_spinner($tabs_spinner);
	$self->elm_unexpand_check($unexpand_check);
	$self->elm_expand_check($expand_check);
	$self->elm_settings_win($settings_win);
	
	# Callbacks
	$cancel_btn->smart_callback_add("clicked", sub { $settings_win->del() }, undef );
	$ok_btn->smart_callback_add("clicked", \&save_settings, $self);
	
	$settings_win->resize_object_add($bx);
	$settings_win->resize(250,200);
	
	$settings_win->show();
	
	return $settings_win;
}

sub save_settings {
	my ($self, $obj, $ev) = @_;
	
	my $tabs_spinner = $self->elm_tabs_spinner();
	my $unexpand_check = $self->elm_unexpand_check();
	my $expand_check = $self->elm_expand_check();
	
	my $config = {};
	
	$config->{tabstops} = $tabs_spinner->value_get();
	$config->{unexpand} = $unexpand_check->state_get();
	$config->{expand} = $expand_check->state_get();
	
	$self->save_config($config);
	
	return
}

sub load_config {
	my $self = shift;
	
	my $path = File::HomeDir->my_home . "/.esource-highlight/config.yaml";
	
	if (-e $path) {
		open my $fh, "<:encoding(utf-8)", $path or die "Could not open $path: $!\n";
		#flock $fh, LOCK_SH;
		my $yaml ='';
		while (my $line = <$fh>) {$yaml .= $line}
		close $fh;
	
		return Load($yaml);
	}
	else {
		return {};
	}
}

sub save_config {
	my ($self, $config) = @_;
	
	my $path = File::HomeDir->my_home . "/.esource-highlight";
	
	unless (-e $path) {
		make_path $path or die "Could not create $path: $!";
	}
	
	open my $fh, ">:encoding(utf-8)", "$path/config.yaml" or die "Could not open $path: $!\n";
	# flock $fh, LOCK_EX;
	my $yaml = Dump($config);
	print $fh "$yaml";
	close $fh;
}

############################
# Accessors
############################

sub AUTOLOAD {
	my ($self, $newval) = @_;
	
	die("No method $AUTOLOAD implemented\n")
		unless $AUTOLOAD =~m/^app|elm_tabs_spinner|elm_unexpand_check|elm_expand_check|elm_settings_win$/;
	
	my $attrib = $AUTOLOAD;
	$attrib =~ s/.*://;
	
	my $oldval = $self->{$attrib};
	$self->{$attrib} = $newval if defined($newval);
	
	return $oldval;
}

sub DESTROY {}


# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

eSourceHighlight - Perl extension for blah blah blah

=head1 SYNOPSIS

  use eSourceHighlight;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for eSourceHighlight, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Maximilian, E<lt>maximilian@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Maximilian

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.32.1 or,
at your option, any later version of Perl 5 you may have available.


=cut

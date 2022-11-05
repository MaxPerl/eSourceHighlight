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

use Text::Tabs;

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
	
	$self->app($app);
	
	my $settings_win = pEFL::Elm::Win->add($app->elm_mainwindow(), "Settings", ELM_WIN_BASIC);
	$settings_win->title_set("Settings");
	$settings_win->focus_highlight_enabled_set(1);
	$settings_win->autodel_set(1);
	$self->elm_settings_win($settings_win);
	
	my $bg = pEFL::Elm::Bg->add($settings_win);
	$bg->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$bg->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$bg->show(); $settings_win->resize_object_add($bg);
	
	my $container = pEFL::Elm::Table->add($settings_win);
	$container->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$container->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	# $container->padding_set(10,10);
	$container->show(); $settings_win->resize_object_add($container);
	
	my $tb = pEFL::Elm::Toolbar->add($container);
	$tb->shrink_mode_set(ELM_TOOLBAR_SHRINK_SCROLL);
	$tb->select_mode_set(ELM_OBJECT_SELECT_MODE_ALWAYS);
	$tb->homogeneous_set(0);
	$tb->horizontal_set(0);
	$tb->align_set(0.0);
	$tb->size_hint_weight_set(0.0,EVAS_HINT_EXPAND);
	$tb->size_hint_align_set(0.0,EVAS_HINT_FILL);
	$tb->show(); $container->pack($tb,0,0,1,5);
	
	my $naviframe = pEFL::Elm::Naviframe->add($settings_win);
	$naviframe->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$naviframe->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$naviframe->show();
	#$table->homogeneous_set(1);
	$container->pack($naviframe,1,0,4,5);
	
	my $settings_appearance_it = $naviframe->item_push("",undef,undef,$self->_settings_appearance_create($naviframe),undef);
	$settings_appearance_it->title_enabled_set(0,0);
	my $settings_tabulator_it = $naviframe->item_push("",undef,undef,$self->_settings_tabulator_create($naviframe),undef);
	$settings_tabulator_it->title_enabled_set(0,0);
	
	my $tab_item = $tb->item_append("preferences-desktop-font","Appearance",\&_settings_category_cb, $settings_appearance_it);
	my $tab_item2 = $tb->item_append("applications-development","Tabulator",\&_settings_category_cb, $settings_tabulator_it);
	
	$tab_item->selected_set(1);
	
	$settings_win->resize(480,360);
	
	$settings_win->show();
	
	return $settings_win;
}

sub _settings_category_cb {
	my ($it) = @_;
	$it->promote();
}

sub _add_buttons {
	my ($self,$table,$row) = @_;
	
	my $btn_bx = pEFL::Elm::Box->add($table);
	$btn_bx->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$btn_bx->size_hint_align_set(EVAS_HINT_FILL, 0);
	$btn_bx->horizontal_set(1);
	$btn_bx->show(); $table->pack($btn_bx,0,$row,2,1);
	
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
	
	# Callbacks
	$cancel_btn->smart_callback_add("clicked", sub { $self->elm_settings_win()->del(); }, undef );
	$ok_btn->smart_callback_add("clicked", \&save_settings, $self);
	
	return $btn_bx;
}

sub _settings_tabulator_create {
	my ($self,$parent) = @_;
	
	my $config = $self->load_config();
	
	my $box = pEFL::Elm::Box->add($parent);
	$box->horizontal_set(0);
	$box->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$box->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$box->show();
	
	my $frame = pEFL::Elm::Frame->add($parent);
	$frame->text_set("Tabulator settings");
	$frame->part_content_set("default",$box);
	$frame->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$frame->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$frame->show();
	
	my $table = pEFL::Elm::Table->add($parent);
	$table->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$table->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$table->padding_set(10,10);
	$table->show(); $box->pack_end($table);
	
	my $tabs_label = pEFL::Elm::Label->new($table);
	#$tabs_label->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	#$tabs_label->size_hint_align_set(EVAS_HINT_FILL,0);
	$tabs_label->text_set("Tabstops");
	$tabs_label->show(); $table->pack($tabs_label,0,2,1,1);
	
	my $tabs_spinner = pEFL::Elm::Spinner->add($table);
	$tabs_spinner->value_set($config->{tabstops} || 4);
	$tabs_spinner->size_hint_align_set(EVAS_HINT_FILL,0);
	$tabs_spinner->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$tabs_spinner->show(); $table->pack($tabs_spinner,1,2,1,1);
	
	my $tabmode_combo = pEFL::Elm::Combobox->add($table);
	$tabmode_combo->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$tabmode_combo->size_hint_align_set(EVAS_HINT_FILL,0);
	my $tabmode = $config->{tabmode} || "Tabulator mode";
	$tabmode_combo->text_set($tabmode);
	# elm_object_part_content_set(hoversel, "icon", rect);
	my $itc = pEFL::Elm::GenlistItemClass->new();
	$itc->item_style("default");
	$itc->text_get(sub {return $_[0];});
	$tabmode_combo->item_append($itc,"Add tabulators",undef,ELM_GENLIST_ITEM_NONE,undef,undef);
	$tabmode_combo->item_append($itc,"Add whitespace",undef,ELM_GENLIST_ITEM_NONE,undef,undef);
	$tabmode_combo->smart_callback_add("item,pressed",\&_combobox_item_pressed_cb, undef);
	$tabmode_combo->show(); $table->pack($tabmode_combo,0,3,2,1);
	
	my $header2 = pEFL::Elm::Label->add($table);
	$header2->text_set("<b>Customize when opening a file</b>");
	$header2->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$header2->size_hint_align_set(0,0);
	#$header2->align_set(0.0);
	$header2->show(); $table->pack($header2,0,4,2,1);
	
	my $unexpand_check = pEFL::Elm::Check->add($table);
	$unexpand_check->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$unexpand_check->size_hint_align_set(EVAS_HINT_FILL,0);
	$unexpand_check->text_set("Unexpand white space to tabs");
	$unexpand_check->state_set(1) if ($config->{unexpand_tabs});
	$unexpand_check->show(); $table->pack($unexpand_check,0,5,2,1);
	
	my $expand_check = pEFL::Elm::Check->add($table);
	$expand_check->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$expand_check->size_hint_align_set(EVAS_HINT_FILL,0);
	$expand_check->text_set("Expand tabs to white space");
	$expand_check->state_set(1) if ($config->{expand_tabs});
	$expand_check->show(); $table->pack($expand_check,0,6,2,1);
	
	# Save important widgets
	$self->elm_tabs_spinner($tabs_spinner);
	$self->elm_tabmode_combo($tabmode_combo);
	$self->elm_unexpand_check($unexpand_check);
	$self->elm_expand_check($expand_check);
	
	$self->_add_buttons($table,7);
	
	return $frame;
}

sub _settings_appearance_create {
	my ($self,$parent) = @_;
	
	my $config = $self->load_config();
	
	my $box = pEFL::Elm::Box->add($parent);
	$box->horizontal_set(0);
	$box->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$box->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$box->show();
	
	my $frame = pEFL::Elm::Frame->add($parent);
	$frame->text_set("Appearance settings");
	$frame->part_content_set("default",$box);
	$frame->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$frame->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	
	$frame->show();
	
	my $table = pEFL::Elm::Table->add($parent);
	$table->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$table->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$table->padding_set(10,10);
	$table->show(); $box->pack_end($table);
	
	my $font_combo = pEFL::Elm::Combobox->add($table);
	$font_combo->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$font_combo->size_hint_align_set(EVAS_HINT_FILL,0);
	my $font = $config->{font} || "Font";
	$font_combo->text_set($font);
	
	my $itc = pEFL::Elm::GenlistItemClass->new();
	$itc->item_style("default");
	$itc->text_get(sub {return $_[0];});
	my @fonts = $box->evas_get->font_available_list_pv();
	my @mono = ();
	foreach my $font (@fonts) {
		if ($font =~ m/[mM]ono/) {
			$font =~ s/:style.*$//;
			$font =~ s/,.*$//;
			push @mono, $font if (!grep /^$font$/, @mono);
			
		}
	}
	@mono = sort(@mono);
	foreach my $f (@mono) {
		$font_combo->item_append($itc,$f,undef,ELM_GENLIST_ITEM_NONE,undef,undef);
	}
	$font_combo->smart_callback_add("item,pressed",\&_combobox_item_pressed_cb, undef);
	$font_combo->show(); $table->pack($font_combo,0,1,2,1);
	
	my $tabs_label = pEFL::Elm::Label->new($table);
	#$tabs_label->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	#$tabs_label->size_hint_align_set(0.1,EVAS_HINT_FILL);
	$tabs_label->text_set("Font size");
	$tabs_label->show(); $table->pack($tabs_label,0,2,1,1);
	
	my $font_size_spinner = pEFL::Elm::Slider->add($table);
	$font_size_spinner->size_hint_align_set(EVAS_HINT_FILL,0.5);
	$font_size_spinner->size_hint_weight_set(EVAS_HINT_EXPAND,0.0);
	$font_size_spinner->unit_format_set("%1.0f");
	$font_size_spinner->indicator_format_set("%1.0f");
	$font_size_spinner->min_max_set(6,24);
	$font_size_spinner->step_set(1);
	$font_size_spinner->value_set($config->{font_size} || 10.0);
	$font_size_spinner->show(); $table->pack($font_size_spinner,1,2,1,1);
		
	# Save important widgets
	$self->elm_font_size_slider($font_size_spinner);
	$self->elm_font_combo($font_combo);
	
	$self->_add_buttons($table,3);
	
	return $frame;
}


sub _combobox_item_pressed_cb {
	my ($data,$obj,$event_info) = @_;
	my $item = pEFL::ev_info2obj($event_info, "ElmGenlistItemPtr");
	my $text = $item->text_get();
	$obj->text_set($text);
	$obj->hover_end();
}

sub save_settings {
	my ($self, $obj, $ev) = @_;
	
	my $tabs_spinner = $self->elm_tabs_spinner();
	my $tabmode_combo = $self->elm_tabmode_combo();
	my $unexpand_check = $self->elm_unexpand_check();
	my $expand_check = $self->elm_expand_check();
	my $font_size_slider = $self->elm_font_size_slider();
	my $font_combo = $self->elm_font_combo();
	
	my $config = {};
	
	$config->{tabstops} = $tabs_spinner->value_get();
	$config->{tabmode} = $tabmode_combo->text_get();
	$config->{unexpand_tabs} = $unexpand_check->state_get();
	$config->{expand_tabs} = $expand_check->state_get();
	my $font = $font_combo->text_get() || "Monospace";
	$font =~ s/ //g;
	$config->{font} = $font;
	
	$config->{font_size} = int($font_size_slider->value_get());
	
	my $entry = $self->app->entry();
	my $en = $entry->elm_entry();
	
	my $font_size = $config->{font_size} || 10;
	
	my $user_style = qq(DEFAULT='font=$font:style=Regular font_size=$font_size');
	my $w = $entry->_calc_em($user_style);
	
	$tabstop = $config->{tabstops} || 4;
	my $tabs = $w * $tabstop;
	
	$user_style = qq(DEFAULT='font=$font:style=Regular font_size=$font_size tabstops=$tabs');
	$en->text_style_user_push($user_style);
	
	#$self->app->entry->rehighlight_all();
	
	if ($tabmode_combo->text_get() eq "Add whitespace") {
		$self->app->entry->tabmode("whitespaces");
	}
	else {
		$self->app->entry->tabmode("tabs");
	}
	
	$self->save_config($config);
	
	$self->elm_settings_win()->del();
	
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
		unless $AUTOLOAD =~m/::(app|elm_tabs_spinner|elm_tabmode_combo|elm_unexpand_check|elm_expand_check|elm_font_size_slider|elm_font_combo|elm_settings_win)$/;
	
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

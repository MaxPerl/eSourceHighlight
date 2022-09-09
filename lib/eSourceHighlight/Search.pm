package eSourceHighlight::Search;

use 5.006001;
use strict;
use warnings;
use utf8;

require Exporter;

use Efl::Elm;
use Efl::Evas;
use Encode;

use eSourceHighlight::Entry;

our @ISA = qw(Exporter);

our $AUTOLOAD;

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use eSourceHighlight ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

sub new {
	my ($class, $app, $box, %opts) = @_;
	
	# Get index

	my $obj = {
		app => $app,
		elm_entry => undef,
		found => [],
		parent => undef,
		elm_replace_entry => undef,
		elm_widget => undef,
		elm_search_button => undef,
		keysearch => "no",
		refocus_replace => "no",
		};
	bless($obj,$class);
	$obj->init_search($app,$box);
	return $obj;
}

sub init_search {
	my ($self, $app,$vbox) = @_;
	my $parent = $self->app->elm_mainwindow();
	my $big_box = Efl::Elm::Box->add($self->app->elm_mainwindow());
	$big_box->size_hint_align_set(EVAS_HINT_FILL, 0.5);
	$big_box->size_hint_weight_set(EVAS_HINT_EXPAND,0.0);
	
	my $box = Efl::Elm::Box->add($parent);
	$box->homogeneous_set(0);
	$box->padding_set(15,0);
	$box->horizontal_set(1);
	$box->size_hint_align_set(EVAS_HINT_FILL, EVAS_HINT_FILL);
	$box->size_hint_weight_set(EVAS_HINT_EXPAND,0.0);
	$big_box->pack_end($box);
	$box->show();
	
	my $table = Efl::Elm::Table->add($parent);
	$table->size_hint_align_set(EVAS_HINT_FILL, EVAS_HINT_FILL);
	$table->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$table->padding_set(5,0);
	
	
	my $lbl = Efl::Elm::Label->add($table);
	$lbl->text_set("Search term");
	$lbl->size_hint_align_set(EVAS_HINT_FILL, 0.5);
	$lbl->size_hint_weight_set(0.0, 0.0);
	$table->pack($lbl, 0, 0, 1, 1);
	$lbl->show();
   	
   	my $entry = Efl::Elm::Entry->add($table);
   	$entry->scrollable_set(1);
   	$entry->single_line_set(1);
   	$entry->size_hint_align_set(EVAS_HINT_FILL, 0.0);
   	$entry->size_hint_weight_set(EVAS_HINT_EXPAND, 0.0);
   	$table->pack($entry, 1, 0, 1, 1);
   	$entry->show();
   	
   	$entry->smart_callback_add("changed",\&search_entry_changed,$self);
   	$entry->smart_callback_add("activated",\&search_entry_activated,$self);
   	$entry->smart_callback_add("aborted",\&search_aborted,$self);
   	$self->app->entry->elm_entry->smart_callback_add("selection,changed",\&unfocused_cb,$self);
   	
   	#$entry->event_callback_add(EVAS_CALLBACK_KEY_UP, \&search_entry_key_down, $self);
   	
   	my $replace_lbl = Efl::Elm::Label->add($table);
   	$replace_lbl->text_set("Replace term");
   	$replace_lbl->size_hint_align_set(EVAS_HINT_FILL, 0.5);
   	$replace_lbl->size_hint_weight_set(0.0, 0.0);
   	$table->pack($replace_lbl, 0, 1, 1, 1);
   	$replace_lbl->show();
   	
   	my $replace_entry = Efl::Elm::Entry->add($table);
   	$replace_entry->scrollable_set(1);
   	$replace_entry->single_line_set(1);
   	$replace_entry->size_hint_align_set(EVAS_HINT_FILL, 0.0);
   	$replace_entry->size_hint_weight_set(EVAS_HINT_EXPAND, 0.0);
   	$table->pack($replace_entry, 1, 1, 1, 1);
   	$replace_entry->show();
   	$replace_entry->smart_callback_add("changed",\&search_entry_changed,$self);
   	$replace_entry->smart_callback_add("activated",\&replace_entry_activated,$self);
   	$replace_entry->smart_callback_add("aborted",\&search_aborted,$self);
   	
	$table->show();
	$big_box->pack_end($table);
   	
	my $box2 = Efl::Elm::Box->add($parent);
	$box2->homogeneous_set(0);
	$box2->padding_set(15,0);
	$box2->horizontal_set(1);
	$box2->size_hint_align_set(1.0, EVAS_HINT_FILL);
	$box2->size_hint_weight_set(0.0,0.0);
	$box2->show();
	$big_box->pack_end($box2);
	
	my $wrapped_text = Efl::Elm::Label->add($parent);
	$wrapped_text->text_set("Reached end of file, starting from beginning");
	$box2->pack_end($wrapped_text);
	
	my $btn = Efl::Elm::Button->add($parent);
	$btn->text_set("Search");
	$btn->size_hint_align_set(1.0, 0.0);
	$btn->size_hint_weight_set(0.0, 0.0);  
	$btn->show();
	$box2->pack_end($btn);
	$btn->smart_callback_add("clicked", \&search_clicked, $self);
	
	my $replace_btn = Efl::Elm::Button->add($parent);
	$replace_btn->text_set("Replace");
	$replace_btn->size_hint_align_set(1.0, 0.0);
	$replace_btn->size_hint_weight_set(0.0, 0.0);
	$replace_btn->show();
	$box2->pack_end($replace_btn);
	$replace_btn->smart_callback_add("clicked", \&replace_clicked, $self);
   	
	my $cancel_btn = Efl::Elm::Button->add($parent);
	$cancel_btn->text_set("Cancel");
	$cancel_btn->size_hint_align_set(1.0, 0.0);
	$cancel_btn->size_hint_weight_set(0.0, 0.0);
	$cancel_btn->show();
	$box2->pack_end($cancel_btn);
	$cancel_btn->smart_callback_add("clicked", \&cancel_clicked, $app->entry);
	
	$self->elm_entry($entry);
	$self->elm_replace_entry($replace_entry);
	$self->elm_search_button($btn);
	$self->elm_widget($big_box);
	$app->entry->search($self);
   	
}


sub search_entry_changed {
	my ($self, $obj,$data) = @_;
	
	$self->clear_search_results();
}


sub do_search {
	my ($search, $entry) = @_;
	
	my $en = $entry->elm_entry();
	my $text_markup = $search->elm_entry()->text_get();
	my $text = Efl::Elm::Entry::markup_to_utf8($text_markup);
	
	return unless ($text);
	$text = Encode::decode("UTF8",$text,Encode::FB_CROAK);
	
	# Workaround that length works properly on the Elementary Utf8 Format
	#Encode::_utf8_on($text);
	#print "TEXT DECODED " . Encode::decode("utf-8", $text) . "\n";
	#my $length = length(Encode::decode("UTF8",$text));
	my $length = length($text);
	#Encode::_utf8_off($text);
	
	my $cursor_pos = $en->cursor_pos_get();
	
	if (scalar( @{$search->found} ) < 1 ) {
		my @found;
		my $textblock = $en->textblock_get();
		my $cp = Efl::Evas::TextblockCursor->new($textblock);
		
		while (1) {
			$cp->line_char_first();
			my $line_char_first = $cp->pos_get();
			
			my $line_text = $cp->paragraph_text_get(); 
			$line_text = Efl::Elm::Entry::markup_to_utf8($line_text);
			$line_text = Encode::decode("UTF8",$line_text,Encode::FB_CROAK);
			
			my $col; my $start = 0;
			while ( ( $col = index($line_text,$text,$start) ) != -1 ) {
				#my $find_cp = Efl::Evas::TextblockCursor->new($textblock);
				#$find_cp->pos_set($line_char_first + $col);
				my $find_cp = $line_char_first + $col;
				push @found, $find_cp; 
				$start++;
			}
			
			last unless ($cp->paragraph_next());
		}
		
		$search->found(\@found);
		$cp->free();
	}
	
	return if (scalar( @{$search->found} ) < 1);
	my $i;
	
	my $last_index = scalar( @{$search->found} ) - 1;
	for ($i=0; $i <= $last_index; $i++) { 
		
		my $found_pos = $search->found->[$i];
		
		# If you reached the last element, start from the beginning
		if (($i == $last_index) && ($cursor_pos > $found_pos)) {
			$found_pos = $search->found->[0];
			$en->cursor_pos_set($found_pos);
			$en->select_region_set($found_pos, $found_pos + $length);
			last;
		}
		elsif ($cursor_pos > $found_pos ) {
			next;
		}
		else {
			$en->cursor_pos_set($found_pos);
			$en->select_region_set($found_pos, $found_pos + $length);
			last;
		}
	}
	
}

sub clear_search_results {
	my ($self) = @_;
	
	$self->found([]);
}

sub search_aborted {
	my ($self, $obj, $ev) = @_;
	$self->app->toggle_find($self->app);
}

sub search_entry_activated {
	my ($self, $obj, $ev) = @_;
	$self->do_search($self->app->entry);
	$self->keysearch("yes");
}

sub replace_entry_activated {
	my ($self, $obj, $ev) = @_;
	$self->replace_clicked();
	$self->refocus_replace("yes");
}

sub unfocused_cb {
	my ($self, $obj) = @_;

	if ($self->keysearch() eq "yes") {
		$self->keysearch("no");
		$self->elm_entry->focus_set(1);
	}
	elsif ($self->refocus_replace eq "yes") {
		$self->refocus_replace("no");
		$self->elm_replace_entry->focus_set(1);
	}
}

sub search_clicked {
	my ($self, $obj, $ev) = @_;
	
	my $search = $self->app->entry->search();
	
	if (defined($search)) {
		$search->do_search($self->app->entry);
	}
}



sub replace_clicked {
	my ($self, $obj, $ev) = @_;
	
	my $entry = $self->app->entry();
	my $en = $entry->elm_entry();
	my $cpos = $en->cursor_pos_get();
	my $stext_markup = $self->elm_entry()->text_get();
	my $stext = Efl::Elm::Entry::markup_to_utf8($stext_markup);
	
	return unless ($stext);
	
	my $rtext_markup = $self->elm_replace_entry()->text_get();
	my $rtext = Efl::Elm::Entry::markup_to_utf8($rtext_markup);
	
	my $selected_text = $en->selection_get() || "";
	
	if ($stext eq $selected_text) {
		$en->entry_insert($rtext);
		$en->select_none();$en->cursor_pos_set($cpos);
		$self->do_search($entry);
	}
	else {
		$self->do_search($entry);
	}
}


sub cancel_clicked {
	my ($self,$obj,$ev) = @_;
	
	$self->clear_search_results;
	
	$self->app->toggle_find(undef,undef);
	

}

############################
# Accessors
############################

sub current_search_line {
	my ($self, $newval) = @_;
	
	my $oldval = $self->{current_search_line};
	$self->{current_search_line} = $newval;
	
	return $oldval;
}

sub current_search_column {
	my ($self, $newval) = @_;
	
	my $oldval = $self->{current_search_column};
	$self->{current_search_column} = $newval;
	
	return $oldval;
}

sub AUTOLOAD {
	my ($self, $newval) = @_;
	
	die("No method $AUTOLOAD implemented\n") unless $AUTOLOAD =~m/app|keysearch|refocus_replace|found|elm_entry|elm_replace_entry|elm_widget|elm_search_button|$/;
	
	my $attrib = $AUTOLOAD;
	$attrib =~ s/.*://;
	
	my $oldval = $self->{$attrib};
	$self->{$attrib} = $newval if $newval;
	
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

package eSourceHighlight::Entry;

use 5.006001;
use strict;
use warnings;
use utf8;

require Exporter;

use Efl::Ecore;
use Efl::Ecore::EventHandler;
use Efl::Ecore::Event::Key;
use Efl::Elm;
use Efl::Evas;

use Syntax::SourceHighlight;
use HTML::Entities;
use Encode;

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
	my ($class, $app, $box) = @_;
	
	# Get index
	
	my $obj = {
		app => $app,
		is_undo => "no",
		is_rehighlight => "no",
		highlight => "no",
		rehighlight => "yes",
		paste => "no",
		linewrap => "yes",
		autoindent => "yes",
		current_line => 0,
		current_col => 0,
		search => undef,
		sh_obj => undef,
		sh_langmap => undef,
		elm_entry => undef,
		};
	bless($obj,$class);
	$obj->init_entry($app,$box);
	return $obj;
}

sub init_entry {
	my ($self,$app,$box) = @_;
	my $share = $app->share_dir();
	my $h1 = Syntax::SourceHighlight->new("$share/myhtml.outlang"); $self->sh_obj($h1);
	$h1->setStyleFile("$share/mystyle.style");
	$h1->setOutputDir("$share"); 
	
	my $lm = Syntax::SourceHighlight::LangMap->new(); $self->sh_langmap($lm);
	
	my $en = Efl::Elm::Entry->add($box);
	$en->scrollable_set(1);
	$en->autosave_set(0);
	$en->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$en->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$en->line_wrap_set(ELM_WRAP_WORD);
	
	#$en->smart_callback_add("selection,paste" => \&on_paste, $self);
	$en->event_callback_add(EVAS_CALLBACK_KEY_DOWN, \&line_column_get, $self);
	$en->event_callback_add(EVAS_CALLBACK_MOUSE_UP, \&line_column_get_mouse, $self);
	$en->smart_callback_add("changed,user" => \&changed, $self);
	
	$en->bounce_set(1,1);
	$en->page_relative_set(1,1);
	
	$box->pack_end($en);
	$en->show();
	
	$self->app->entry($self);
	$self->elm_entry($en);
}


# TODO: Move to eSourceHighlight::Tab
sub determ_source_lang {
	my ($self,$filename) = @_;
	
	my $lm = $self->sh_langmap();
	my $lang;
	if ($filename =~ m/\.pl$/) {
		$lang = "perl.lang";
	}
	else {
		$lang = $lm->getMappedFileNameFromFileName($filename);
	}
	
	# Workaround: Source Highlight 
	$lang = $lang eq "prolog.lang" ? "perl.lang" : $lang;
	$self->app->current_tab->sh_lang($lang);
	
	return;
}


sub changed {
    my ($self, $entry, $ev) = @_;    			 
	#print "\n\nCHANGE\n";
	#print "IS UNDO " . $self->is_undo() . "\n";
	#print "IS REHIGHLIGHT " . $self->is_rehighlight() . "\n";
	#print "REHIGHLIGHT " . $self->rehighlight() . "\n";
	my $change_info = Efl::ev_info2obj($ev,"Efl::Elm::EntryChangeInfo");
	
	my $change = $change_info->change();
	
	
	########################
	# Change Tab name, if changed status has changed
	########################
	my $current_tab = $self->app->current_tab();
	$current_tab->changed($current_tab->changed+1);
	my $elm_it = $current_tab->elm_toolbar_item; 
	my $title = $elm_it->text_get();
	$elm_it->text_set("$title*") if ($current_tab->changed() && $title !~/\*$/);
	$elm_it->text_set("$title") if ($current_tab->changed() == 0 && $title =~/\*$/);
	
	########################
	# Fill undo stack
	########################
	my $new_undo = $self->fill_undo_stack($change_info);
	
	
	###########################
	# Auto indent
	##########################
	$self->auto_indent($entry, $change_info) if ($self->autoindent() eq "yes");
	
	
	##########################
	# Source highlight
	#########################
	if ( $current_tab->source_highlight() eq "yes" ) {
		
		if ($self->rehighlight() eq "yes") {
			$self->rehighlight_lines($entry, $new_undo);	
		}
		else {
			#print "Set rehighlight yes in change\n";
			$self->rehighlight("yes");
		}
	}
	
	######################
	# Clear search results
	######################
	$self->search()->clear_search_results();
	
	#######################
	# get line on del change 
	########################
	$self->get_line_on_del($change_info);
}



########################
# Fill undo stack
########################
sub fill_undo_stack {
	my ($self, $change_info) = @_;
	
	my $current_tab = $self->app->current_tab();
	my $change = $change_info->change();
	
	my @undo_stack = @{$current_tab->undo_stack};
	my $last_undo = $undo_stack[$#undo_stack];
	my $new_undo;
	
	
	if ($self->is_undo() eq "yes") {
		$self->is_undo("no");
		#my $insert_content = $change->{insert}->{content};
		# print "undo found $insert_content\n";
		
	}
	elsif ($self->is_rehighlight() eq "yes") {
		$self->is_rehighlight("no");
		#my $insert_content = $change->{insert}->{content};
		# print "rehighlight found $insert_content\n";
	}
	else {
		undef @{$current_tab->redo_stack};
		
		if ($change_info->insert) {
			
			my $prev_pos = $last_undo->{pos} || 0;
			my $prev_char = $last_undo->{content};
			my $prev_plain_length = $last_undo->{plain_length} || 0;
			
			my $new_pos = $change->{insert}->{pos};
			my $insert_content = $change->{insert}->{content};
			my $new_plain_length = $change->{insert}->{plain_length};
			
			# Make a new undo record, only if a new word starts, a tab is inserted or a newline
			if ($prev_pos == ($new_pos - $prev_plain_length) && $insert_content =~ m/\S/ && $insert_content ne "<br/>" && $insert_content ne "<tab/>" ) {
				pop @{$current_tab->undo_stack};
				$new_undo->{pos} = $prev_pos;
				
				$new_undo->{plain_length} = $prev_plain_length + $new_plain_length;
				$new_undo->{content} = $last_undo->{content} . $insert_content;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			elsif ($insert_content) {
				$new_undo->{pos} = $new_pos;
				my $prev= $insert_content;
				$new_undo->{content} = $insert_content if ($insert_content);
				$new_undo->{plain_length} = $new_plain_length;
				push @{$current_tab->undo_stack}, $new_undo;
			}
				
		}
		else {
			my $prev_start = $last_undo->{start} || 1;
			my $prev_content = $last_undo->{content};
			my $prev_end = $last_undo->{end} || 1;
		
			my $start = $change->{del}->{start};
			my $end = $change->{del}->{end};
			my $content = $change->{del}->{content};
			
			# BackSlash key is pressed
			if ($last_undo->{del} && $prev_start == ($start +1) ) {
				pop @{$current_tab->undo_stack};
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $prev_end;
				$new_undo->{content} = $content . $prev_content;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			# Delete key is pressed
			elsif ($last_undo->{del} && $prev_start == $start && $prev_end == $end) {
				pop @{$current_tab->undo_stack};
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $end;
				$new_undo->{content} = $prev_content . $content;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			# a new area is deleted
			else {
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $end;
				$new_undo->{content} = $content;
				push @{$current_tab->undo_stack}, $new_undo;
			}
		
		}
	}
	
	return $new_undo;
}


###########################
# Auto indent
##########################
sub auto_indent {
	my ($self,$entry,$change_info) = @_;
	
	my $current_tab = $self->app->current_tab();
	my $change = $change_info->change();
	my $cursor_pos = $self->elm_entry->cursor_pos_get();
	
	
	my $content = "";
	if ($change_info->insert()) {
		$content = $change->{insert}->{content};
	}
	
	if ($content eq "<br/>") {		
		$entry->cursor_up();
		$entry->cursor_line_begin_set; $entry->cursor_selection_begin();
		$entry->cursor_line_end_set; $entry->cursor_selection_end();
		
		my $text = $entry->selection_get();
		
		unless ($text) {
			my $current_line = $self->current_line();
			my $i;
			for ($i=$current_line; $i>=0; $i--) {
				$entry->cursor_up();
				$entry->cursor_line_begin_set; $entry->cursor_selection_begin();
				$entry->cursor_line_end_set; $entry->cursor_selection_end();
				
				$text = $entry->selection_get();
				last if ($text);
			}
		}
		# if $entry->insert(undef|"") [e.g. two or more <br> are entered] is called, 
		# then no "change" event is triggered
		# that means: $self->is_undo("yes") applies also to the next change :-S
		# therefore check, whether there is a text
		if ($text) {				
			$self->is_undo("yes");
			$entry->entry_insert($text);
		
			$entry->cursor_pos_set($cursor_pos);
			
			if ($text =~ m/^<tab\/>/ || $text =~ m/^\s/) {
				my $tabs = ""; 
				my $plain_length = 0;
				while ($text =~ s/^ //) {
					$tabs = $tabs . " ";
					$plain_length++;
					print "PLAIN LENGTH $plain_length\n";
				}
				while ($text =~ s/^<tab\/>//) {
					$tabs = $tabs . "<tab\/>";
					$plain_length++;
				}
				$entry->entry_insert($tabs);
				
				# Because there is no selection (?) the "change, MANUAL" event 
				# isn't triggered. Therefore we must push the undo stack manually
				my $auto_indent_undo = {
					content => $tabs,
					plain_length => $plain_length,
					pos => $cursor_pos,
				};
				push @{$current_tab->undo_stack}, $auto_indent_undo;
			}
		}
		else {
			$entry->cursor_pos_set($cursor_pos);
		}	
	}
	
	# For Debugging undo feature
	#if ($self->is_undo eq "no") {
		#print "UNDO " . $self->is_undo() . "\n";
		#print "REHIGHLIGHT " . $self->is_rehighlight() . "\n";
		#use Data::Dumper;
		#print Dumper(@{$current_tab->undo_stack});
	#}
}

sub on_paste {
	my ($self) = @_;
	#print "Set rehighlight yes on paste event\n";
	$self->rehighlight("yes");
}

sub highlight_str {
	my ($self, $text) = @_;
	
	# $entry->selection_get gets the text in markup format!!!
	# Therefore convert it to utf8
	$text = Efl::Elm::Entry::markup_to_utf8($text);
	
	
	# Check whether there is a $sh_lang for the document
	my $sh_obj = $self->sh_obj; 
	my $sh_lm = $self->sh_langmap(); 
	my $sh_lang = $self->app->current_tab->sh_lang(); 
	if (defined($sh_lang)) {
		#decode_entities($text);
		$text = $sh_obj->highlightString($text,$sh_lang);
	}
	# If there is no source highlight by the GNU source-highlight lib
	# we must encode HTML entities (otherwise it is done by source-highlight!!)
	else {
		encode_entities($text,"<>&");
	}
	
	$text =~ s/\n/<br\/>/g;$text =~ s/\t/<tab\/>/g;
	#$str =~ s/&amp;/&/g;$text =~ s/&lt;/</g;$text =~ s/&gt;/>/g;
	
	return $text;
}
# This works if we open an utf8-text file
# I think it could be problematic when pastin markup text???
# then adapt rehighlight lines???
sub rehighlight_all {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	
	#print "Set rehighlight no in rehighlight_all\n";
	$self->rehighlight("no");
	
	my $cursor_pos = $entry->cursor_pos_get();
	
	$entry->select_all();
	my $text = $entry->selection_get();
	
	
	$text = $self->highlight_str($text);      		
	
	# if $entry->insert(undef|"") is called, then no "change" event is triggered
	# that means: $self->is_relight("yes") would apply also to the next change :-S
	# therefore check, whether there is a text
	if ($text) {
		$self->is_rehighlight("yes");
		$entry->entry_insert($text);
	}
	else {
		$self->rehighlight("yes");
	}
	
	$entry->select_none();
	$entry->cursor_pos_set($cursor_pos);

}

# $undo ist the item of the undo stack
sub rehighlight_lines {
	my ($self, $entry, $undo) = @_;
	
	# Check whether there is a $sh_lang for the document
	my $sh_lang = $self->app->current_tab->sh_lang(); 
	return unless (defined($sh_lang));
	
	#print "Set rehighlight no in rehighlight_lines\n";
	$self->rehighlight("no");
	
	my $cursor_pos = $entry->cursor_pos_get();
	
	if (defined($undo)) {
		if ($undo->{del}) {
			# if there is a del event then we relight from the line before 
			# the del event occured
			$entry->cursor_pos_set($undo->{start});
			$entry->cursor_up();
			$entry->cursor_line_begin_set; $entry->cursor_selection_begin();
			
			# .. to the line after the del event
			$entry->cursor_pos_set($undo->{end});
			$entry->cursor_down;$entry->cursor_down;
			$entry->cursor_line_end_set; $entry->cursor_selection_end();
		}
		else {
				
			$entry->cursor_pos_set($undo->{pos});
			$entry->cursor_up();$entry->cursor_up();
			$entry->cursor_line_begin_set; $entry->cursor_selection_begin();
			
			$entry->cursor_pos_set($undo->{pos}+$undo->{plain_length});
			$entry->cursor_down();$entry->cursor_down();
			$entry->cursor_line_end_set; $entry->cursor_selection_end();
		}
	}
	else {
		# Otherwiese we relight from the line before the actual cursor position...
		$entry->cursor_up();
		$entry->cursor_line_begin_set; $entry->cursor_selection_begin();
		
		# .. to the line after the actual cursor position :-)
		$entry->cursor_down;$entry->cursor_down;
		$entry->cursor_line_end_set; $entry->cursor_selection_end();
	}
	my $text = $entry->selection_get();
	
	$text = $self->highlight_str($text);
	
	# if $entry->insert(undef|"") is called, then no "change" event is triggered
	# that means: $self->is_relight("yes") would apply also to the next change :-S
	# therefore check, whether there is a text
	if ($text) {
		$self->is_rehighlight("yes");
		$entry->entry_insert($text);
	}
	else {
		$self->rehighlight("yes");
	}
	$entry->cursor_pos_set($cursor_pos);
	
}

sub clear_highlight {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	my $cursor_pos = $entry->cursor_pos_get();
	my $text = $entry->entry_get();
	
	$text = $self->to_utf8($text);
	
	$entry->entry_set($text);
}

sub to_utf8 {
	my ($self,$text) = @_;
	
	$text = Efl::Elm::Entry::markup_to_utf8($text);
	$text =~ s/\n/<br\/>/g;$text =~ s/\t/<tab\/>/g;
	
	return $text;
}

sub undo {
	my ($self) = @_;
	my $entry = $self->elm_entry();
	
	my $current_tab = $self->app->current_tab();
	
	my $undo = pop @{$current_tab->undo_stack};
	
	unless (defined($undo)) {
		print "no undo found\n"; 
		return;
	}
	push @{$current_tab->redo_stack}, $undo;
	
	if ($undo->{del}) {
		# It seems that if one inserts withous selection
		# the event changed,user is not triggered
		# therefore here $self->is_undo("yes"); is not needed
		$entry->cursor_pos_set($undo->{start});
		$entry->entry_insert($undo->{content});
		$entry->select_none();
		$self->rehighlight_lines($entry);
	}
	elsif ($undo->{pos} >= 0) {
		$self->is_undo("yes");
		
			
		#$entry->select_region_set($undo->{pos} - $undo->{plain_length}, $undo->{pos});
		my $text = $undo->{content}; $text = Efl::Elm::Entry::markup_to_utf8($text); decode_entities($text);
		$entry->select_region_set($undo->{pos}, $undo->{pos} + $undo->{plain_length});
		$entry->entry_insert("");
		$entry->select_none();
	}
	
}

sub redo {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	
	my $current_tab = $self->app->current_tab();
	
	my $redo = pop @{$current_tab->redo_stack};
	return unless( defined($redo) );
	
	push @{$current_tab->undo_stack}, $redo;
	
	if ($redo->{pos} >= 0) {
		# It seems that if one inserts withous selection
		# the event changed,user is not triggered
		# therefore here $self->is_undo("yes") is not needed 
		my $text = $redo->{content}; $text = Efl::Elm::Entry::markup_to_utf8($text); decode_entities($text); 
		#$entry->cursor_pos_set($redo->{pos}-length($text));
		$entry->cursor_pos_set($redo->{pos});
		$entry->entry_insert($redo->{content});
		$self->rehighlight_lines($entry), $redo;
	}
	elsif ($redo->{del}) {
		$self->is_undo("yes");
		
		$entry->select_region_set($redo->{start},$redo->{end});
		$entry->entry_insert("");
	}

}

sub column_get {
	my ($self) = @_;
	my $column;
	
	my $en = $self->elm_entry();
	
	my $textblock = $en->textblock_get();
	my $cp1 = Efl::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($en->cursor_pos_get);
	my $cp2 = Efl::Evas::TextblockCursor->new($textblock);
	$cp2->pos_set($en->cursor_pos_get);
	$cp2->line_char_first();
	
	$column = $cp1->pos_get() - $cp2->pos_get();
	
	$cp1->free();
	$cp2->free();
	
	return $column;
}

sub line_get {
	my ($self) = @_;
	
	my $en = $self->elm_entry();
	my $lines;
	
	my $textblock = $en->textblock_get();
	my $cp1 = Efl::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($en->cursor_pos_get);
	my $cp2 = Efl::Evas::TextblockCursor->new($textblock);
	$cp2->pos_set(0);
	my $text_before = $textblock->range_text_get($cp2,$cp1,EVAS_TEXTBLOCK_TEXT_MARKUP);
		
	$lines = $text_before =~ s/<br\/>/$&/g; 
	if ($lines ==0 ) {
		$lines = 1; 
	} 
	else { 
		$lines = $lines + 1;
	}
		
	return $lines;
}

sub line_column_get {
	my ($self, $evas, $en, $event) = @_;
	my $column; my $lines;
	
	my $label = $self->app->elm_linecolumn_label();
	return unless(defined($label));
	
	$column = $self->column_get();
	
	my $e = Efl::ev_info2obj($event, "Efl::Ecore::Event::Key");
	
	my $keyname = $e->keyname();
	if ($keyname =~ m/Up|Down|KP_Next|KP_Prior|Return/) {
		$lines = $self->line_get();
	}
	
	if ($lines) {
		$label->text_set("Line: $lines Column: $column");
		$self->current_line($lines);
	}
	else {
		my $text = $label->text_get();
		$text =~ s/(.*)Column:.*$/$1Column: $column/;
		$label->text_set($text);
	}

	
}

sub line_column_get_mouse {
	my ($self, $evas, $en, $event) = @_;
	my $column; my $lines;
	
	my $label = $self->app->elm_linecolumn_label();
	return unless(defined($label));
	
	$column = $self->column_get();
	
	my $e = Efl::ev_info2obj( $event, "Efl::Evas::Event::MouseDown");
	
	my $button = $e->button();
	if ($button == 1) {
		$lines = $self->line_get();
	}
	
	if ($lines) {
		$label->text_set("Line: $lines Column: $column");
		$self->current_line($lines);
	}
	else {
		my $text = $label->text_get();
		$text =~ s/(.*)Column:.*$/$1Column: $column/;
		$label->text_set($text);
	}

	
}

sub get_line_on_del {
	my ($self, $change_info) = @_;
	
	unless ($change_info->insert) {
		my $change = $change_info->change();
		my $content = $change->{insert}->{content};
	
		if ($content eq "<br/>") {
			my $line = $self->line_get();
			my $column = $self->column_get();
			my $label = $self->app->elm_linecolumn_label();
			return unless(defined($label));
			$label->text_set("Line: $line Column: $column");
			$self->current_line($line);
		}
	}
}

######################
# Accessors 
#######################

sub AUTOLOAD {
	my ($self, $newval) = @_;
	
	die("No method $AUTOLOAD implemented\n")
		unless $AUTOLOAD =~m/is_undo|is_rehighlight|highlight|rehighlight|current_line|paste|linewrap|autoindent|search|sh_obj|sh_langmap|elm_entry|/;
	
	my $attrib = $AUTOLOAD;
	$attrib =~ s/.*://;
	
	my $oldval = $self->{$attrib};
	$self->{$attrib} = $newval if $newval;
	if ($attrib eq "rehighlight") {
		#print "Highlight set to $newval\n" if $newval;
	}
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

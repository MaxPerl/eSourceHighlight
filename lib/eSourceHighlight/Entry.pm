package eSourceHighlight::Entry;
use 5.006001;
use strict;
use warnings;
use utf8;
use Time::HiRes qw(time);

require Exporter;

use pEFL::Ecore;
use pEFL::Ecore::EventHandler;
use pEFL::Ecore::Event::Key;
use pEFL::Elm;
use pEFL::Evas;

use Syntax::SourceHighlight;
use HTML::Entities;
use Encode;
use Convert::Color;

use Text::Tabs;

our @ISA = qw(Exporter);

our $AUTOLOAD;

sub new {
	my ($class, $app, $box) = @_;
	
	# Get index
	
	my $obj = {
		app => $app,
		is_change_tab => "no",
		is_undo => "no",
		is_rehighlight => "no",
		is_open => "no",
		highlight => "no",
		rehighlight => "yes",
		paste => "no",
		linewrap => "yes",
		autoindent => "yes",
		match_braces => "yes",
		current_line => 0,
		current_column => 0,
		match_braces_fmt => [],
		search => undef,
		tabmode => "tabs",
		sh_obj => undef,
		sh_langmap => undef,
		em => undef,
		elm_entry => undef,
		undo_processing => 0,
		unod_already_done => "no",
		};
	
	bless($obj,$class);
	$obj->init_entry($app,$box);
	return $obj;
}

sub init_entry {
	my ($self,$app,$box) = @_;
	
	
	my $config = $app->settings->load_config();
	$self->tabmode("whitespaces") if ($config->{tabmode} eq "Add whitespace");
	
	my $share = $app->share_dir();
	my $h1 = Syntax::SourceHighlight->new("$share/myhtml.outlang"); $self->sh_obj($h1);
	$h1->setStyleFile("$share/mystyle.style");
	$h1->setOutputDir("$share"); 
	$h1->setOptimize(1);
	
	my $lm = Syntax::SourceHighlight::LangMap->new(); $self->sh_langmap($lm);
	
	my $edj_path = File::HomeDir->my_home . "/.esource-highlight/custom.edj";
	pEFL::Elm::Theme::overlay_add($edj_path);
	
	my $en = pEFL::Elm::Entry->add($box);
	$en->style_set("custom");
	$en->scrollable_set(1);
	$en->autosave_set(0);
	
	# This is necessary because otherwise on paste events sometimes the bold format of 
	# the pasted text encroaches on other parts of the text :-S
	# It shouldn't be a problem, as every change event leads to highlighting a line
	# before and after the inserted text...
	$en->cnp_mode_set(ELM_CNP_MODE_PLAINTEXT());
	$en->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$en->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$en->line_wrap_set(ELM_WRAP_WORD);
	$self->elm_entry($en);
	
	my $textblock = $en->textblock_get();
	#$textblock->legacy_newline_set(1);
	
	my $font = $config->{font} || "Monospace";
	my $font_size = $config->{font_size} || 10;
	my $user_style = "DEFAULT='font=$font:style=Regular font_size=$font_size'";
	my $w = $self->_calc_em($user_style);
	
	my $tabs = $w * 4;
	my $fcolor = "";
	if ($config->{font_color}) {
		my $c = Convert::Color->new("rgb8:" . join(",",@{$config->{font_color}})); 
		$fcolor = " color=#".$c->hex;
	}

	$user_style = "DEFAULT='font=$font:style=Regular font_size=$font_size tabstops=$tabs$fcolor'";
	$en->text_style_user_push($user_style);
	
	$en->markup_filter_append(\&tabs_to_whitespaces, $self);
	
	$en->event_callback_add(EVAS_CALLBACK_KEY_DOWN, \&on_key_down, $self);
	# We make a MOUSE_DOWN event here because with MOUSE UP you cannot select with mouse anymore
	# TODO: match brackets doesn't work anymore with MOUSE_DOWN. Do a seperate MOUSE_UP for this?
	$en->event_callback_add(EVAS_CALLBACK_MOUSE_DOWN, \&line_column_get_mouse, $self);
	#$en->smart_callback_add("selection,paste" => \&paste_selection, $self);
	$en->smart_callback_add("changed,user" => \&changed, $self);
	$en->smart_callback_add("text,set,done" => \&text_set_done, $self);
	
	$box->pack_end($en);
	$en->show();
	
	$self->app->entry($self);
}


sub _calc_em {
	my ($self, $user_style) = @_;
	
	my $en = $self->elm_entry();
	my $textblock = $en->textblock_get();
	
	my $text = $en->entry_get();
	
	$en->text_style_user_push($user_style);
	
	my $cp = pEFL::Evas::TextblockCursor->new($textblock);
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$en->entry_set("m");
	$cp1->pos_set(1);
	$cp->pos_set(0);
	my @rects = $textblock->range_geometry_get_pv($cp,$cp1);
	my $w = $rects[0]->w();
	$cp1->free();$cp->free();
	
	$self->em($w);
	
	$en->entry_set($text);
	
	return $w;
}

sub paste_selection {
	my $self = shift;
	my $en = $self->elm_entry();
	my $textblock = $en->textblock_get();
	_remove_match_braces($self,$textblock);
}

sub on_key_down {
	my ($self, $evas, $en, $event) = @_;
	
	my $e = pEFL::ev_info2obj($event, "pEFL::Evas::Event::KeyDown");
	my $mod = $e->modifiers();
	my $keyname = $e->keyname();
	
	
	$self->line_column_get($evas, $en, $e);
	
	if ($self->match_braces eq "yes" && $keyname =~ m/Up|KP_Prior|Down|KP_Next|Right|Left|Return/) {
		$self->highlight_match_braces();
	}
	
	#tab_selection($self, $en) if ($keyname eq "Tab" && $mod->key_modifier_is_set("Control"));
	
	if ($keyname =~ m/Up|Down|Return/ && $self->app->current_tab->source_highlight() eq "yes" ) {
		rehighlight_visible_range($self) unless ($mod->key_modifier_is_set("Shift"));
	}
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
	
	$self->app->current_tab->sh_lang($lang) if ($lang);
	
	return;
}

# Problem: 1) We wan't content always be plain utf8! 
# 2) In $change->{insert}->{plain_length} are \n = <br/>,
# Tabs = <tab/> and umlauts &ouml;. Therefore the length is longer than utf8
# with the following we correct plain length
sub _correct_change {
	my ($change_info, $change) = @_;
	
	if ($change_info->insert()) {
		$change->{insert}->{content} = pEFL::Elm::Entry::markup_to_utf8($change->{insert}->{content});
		$change->{insert}->{content} = Encode::decode("UTF-8",$change->{insert}->{content}); 
		$change->{insert}->{plain_length} = length($change->{insert}->{content});
	}
	else {	
		$change->{del}->{content} = pEFL::Elm::Entry::markup_to_utf8($change->{del}->{content});
		$change->{del}->{content} = Encode::decode("UTF-8",$change->{del}->{content});
	}
	
	return $change;
}

sub changed {
	my ($self, $entry, $ev) = @_;
	#print "\n\nCHANGE\n";
	#print "IS UNDO " . $self->is_undo() . "\n";
	#print "IS REHIGHLIGHT " . $self->is_rehighlight() . "\n";
	#print "REHIGHLIGHT " . $self->rehighlight() . "\n";
	
	my $change_info = pEFL::ev_info2obj($ev,"pEFL::Elm::EntryChangeInfo");
	
	my $change = $change_info->change();
	$change = _correct_change($change_info, $change);
	
	my $cpos = $entry->cursor_pos_get();
	
	
	########################
	# Change Tab name, if changed status has changed
	########################
	my $current_tab = $self->app->current_tab();
	$current_tab->changed($current_tab->changed()+1) if ($self->is_undo() eq "no" && $self->is_rehighlight() eq "no");
	my $elm_it = $current_tab->elm_toolbar_item; 
	my $title = $elm_it->text_get();
	$elm_it->text_set("$title*") if ($current_tab->changed() && $title !~/\*$/);
	$elm_it->text_set("$title") if ($current_tab->changed() == 0 && $title =~/\*$/);
	
	########################
	# Fill undo stack
	########################
	my $new_undo = $self->fill_undo_stack($change_info, $change);
	
	
	###########################
	# Auto indent
	##########################
	my $new_cp = $self->auto_indent($entry, $change_info) if ($self->autoindent() eq "yes");
	
		
	##########################
	# Source highlight
	#########################
	my $textblock = $entry->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($entry->cursor_pos_get());
	my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp2->pos_set($entry->cursor_pos_get());
	
	my $text = $self->get_rehighlight_lines($cp1,$cp2);
	
	if ( $current_tab->source_highlight() eq "yes" ) {
		$text = $self->highlight_str($text);
	}
	
	
	#########################
	# resize and format tabs / format newlines
	########################
	#unless ($self->tabmode() eq "whitespaces") {
	if ($text =~ /\t/) {
		$text = $self->resize_tabs($text) if ($text);
		$text = $self->highlight_resized_tabs($text, "<tabstops=(\\d*)>");
		$text =~ s/\t/<tab\/>/g;
	}
	#}
	
	$text =~ s/\n/<br\/>/g; 
	
	$self->set_rehighlight_lines($textblock,$cp1,$cp2,$text);
	$entry->calc_force;
	
	$cp1->free();
	$cp2->free();
	
	
	######################
	# Clear search results
	######################
	$self->search()->clear_search_results();
	
	#######################
	# get line on del change 
	########################
	$self->get_line_on_del($change_info);
	
	$cpos = $new_cp ? $new_cp : $cpos;
	$entry->cursor_pos_set($cpos);
}

sub rehighlight_visible_range {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	my $cpos = $entry->cursor_pos_get();

	##########################
	# Source highlight
	#########################
	my $textblock = $entry->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->visible_range_get($cp2);
	
	my $text = $cp1->range_text_get($cp2,EVAS_TEXTBLOCK_TEXT_PLAIN);
	$text = Encode::decode("UTF-8",$text);
	
	if ( $self->app->current_tab()->source_highlight() eq "yes" ) {
		$text = $self->highlight_str($text);
	}
	
	
	#########################
	# resize and format tabs / format newlines
	########################
	#unless ($self->tabmode() eq "whitespaces") {
	if ($text =~ /\t/) {
		$text = $self->resize_tabs($text) if ($text);
		$text = $self->highlight_resized_tabs($text, "<tabstops=(\\d*)>");
		$text =~ s/\t/<tab\/>/g;
	}
	#}
	
	$text =~ s/\n/<br\/>/g; 
	
	$self->set_rehighlight_lines($textblock,$cp1,$cp2,$text);
	$entry->calc_force;
	$cp1->free();
	$cp2->free();
	
	$entry->cursor_pos_set($cpos);
}

sub _remove_match_braces {
	my ($self,$textblock) = @_;
	
	if (scalar( @{ $self->match_braces_fmt}) >= 1) {
	
		foreach my $fcp (@{$self->match_braces_fmt}) {
			my $fcp2 = pEFL::Evas::TextblockCursor->new($textblock);
			$fcp2->pos_set($fcp->pos_get()); $fcp2->char_next();$fcp2->char_next();
			
			my $fcp3 = pEFL::Evas::TextblockCursor->new($textblock);
			$fcp3->pos_set($fcp->pos_get()); $fcp3->char_prev();$fcp3->char_prev();
			
			my $text = $fcp3->range_text_get($fcp2, EVAS_TEXTBLOCK_TEXT_MARKUP); 
			my @formats = $fcp3->range_formats_get_pv($fcp2);
			foreach my $format (@formats) {
				my $success = $textblock->node_format_remove_pair($format) if ($format->text_get() eq "+ font_weight=bold");
			}
			$fcp->free();
			$fcp2->free();
			$fcp3->free();
		}
		$self->match_braces_fmt([]);
	}
}

sub highlight_match_braces {
	my ($self) = @_;
	my $en = $self->elm_entry();
	
	my $textblock = $en->textblock_get();
	_remove_match_braces($self,$textblock);
	
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($en->cursor_pos_get);
	$cp2->pos_set($en->cursor_pos_get); $cp2->char_next();
	my $char = $textblock->range_text_get($cp1,$cp2,EVAS_TEXTBLOCK_TEXT_PLAIN) || "";
	
	
	if ($char =~ m/^[\)\}\]]$/) {
		my $depth = -1;
		my $match_char;
		if ($char eq ")") {
			$match_char = "(";
		}
		elsif ($char eq "}") {
			$match_char = "{";
		}
		elsif ($char eq "]") {
			$match_char = "[";
		}
		
		$cp1->paragraph_char_first();
		my $text = $textblock->range_text_get($cp1,$cp2,EVAS_TEXTBLOCK_TEXT_PLAIN);
		$text = Encode::decode("UTF-8",$text);
		
		my $start = $cp2->pos_get() - $cp1->pos_get();
		
		while (1) {
			my $match_pos = rindex($text,$match_char,$start);
			my $search_pos = rindex($text, $char,$start);
			
			if ($match_pos == -1 && $search_pos == -1) {
				last if ($cp1->pos_get() == 0);
				$cp1->paragraph_prev();
				$text = $cp1->paragraph_text_get();$cp1->paragraph_char_first();
				$text = pEFL::Elm::Entry::markup_to_utf8($text);
				$text = Encode::decode("UTF-8",$text);
				
				
				$start = length($text);
			}
			elsif ($match_pos == -1 && $search_pos != -1) {
				$depth = $depth + 1;
				$start = $search_pos-1;
				if ($start == -1) {
					$cp1->paragraph_prev(); 
					$text = $cp1->paragraph_text_get(); $cp1->paragraph_char_first();
					$text = pEFL::Elm::Entry::markup_to_utf8($text);
					
					#$text = Encode::decode("UTF-8",$text);
					
					$start = length($text);
				}
			}
			elsif ($search_pos == -1 && $match_pos != -1 && $depth != 0) {
				$depth--;
				$start = $match_pos-1;
				# problem: If match_pos == -1, then the loop never stops
				if ($start == -1) {
					$cp1->paragraph_prev();
					$text = $cp1->paragraph_text_get();$cp1->paragraph_char_first();
					$text = pEFL::Elm::Entry::markup_to_utf8($text);
					$text = Encode::decode("UTF-8",$text);
					
					
					$start = length($text);
				}
			}
			elsif ($match_pos >$search_pos && $depth == 0) {
				my $format_cp1 = pEFL::Evas::TextblockCursor->new($textblock);
				my $format_cp2 = pEFL::Evas::TextblockCursor->new($textblock);
				my $found = $cp1->pos_get+$match_pos;
				$cp1->pos_set($cp1->pos_get+$match_pos);
				$cp1->copy($format_cp1);
				push @{$self->match_braces_fmt}, $format_cp1; 
				$cp1->format_append("<font_weight=bold>"); 
				$cp1->char_next(); 
				$cp1->format_append("</font_weight>");
				
				$cp2->char_prev(); 
				$cp2->copy($format_cp2);
				push @{$self->match_braces_fmt}, $format_cp2;
				$cp2->format_append("<font_weight=bold>"); 
				$cp2->char_next(); 
				$cp2->format_append("</font_weight>");
				  
				last;
			}
			else {
				$start = $match_pos > $search_pos ? $match_pos : $search_pos;
				$start--;
				$depth = $match_pos > $search_pos ? ($depth-1) : ($depth + 1);
			}
		}
		
	}
	elsif ($char =~ m/^[\(\{\[]$/) {
		my $depth = 0;
		my $match_char;
		if ($char eq "(") {
			$match_char = ")";
		}
		elsif ($char eq "{") {
			$match_char = "}";
		}
		elsif ($char eq "[") {
			$match_char = "]";
		}
		
		$cp1->line_char_last();  
		my $text = $textblock->range_text_get($cp2,$cp1,EVAS_TEXTBLOCK_TEXT_PLAIN);
		$text = Encode::decode("UTF-8",$text);
		
		my $found = undef; my $start = 0;
		$cp1->pos_set($cp2->pos_get());
		
		while (1) {
			my $match_pos = index($text,$match_char,$start);
			my $search_pos = index($text, $char,$start);
			if ($match_pos == -1 && $search_pos == -1) {
				last if (!$cp1->paragraph_next);
				$cp1->paragraph_char_first();
				$text = $cp1->paragraph_text_get();
				$text = pEFL::Elm::Entry::markup_to_utf8($text);
				$text = Encode::decode("UTF-8",$text);
				
				
				$start = 0;
			}
			elsif ($match_pos == -1 && $search_pos != -1) {
				$depth = $depth + 1;
				$start = $search_pos+1;
				if ($start == (length($text)-1)) {
					$cp1->paragraph_next(); $cp1->paragraph_char_first();
					$text = $cp1->paragraph_text_get();
					$text = pEFL::Elm::Entry::markup_to_utf8($text);
					$text = Encode::decode("UTF-8",$text);
					
					
					$start = 0;
				}
			}
			elsif (($match_pos < $search_pos && $depth == 0) || ($search_pos == -1 && $match_pos != -1 && $depth == 0) ) {
				my $format_cp1 = pEFL::Evas::TextblockCursor->new($textblock);
				my $format_cp2 = pEFL::Evas::TextblockCursor->new($textblock);
				$cp1->pos_set($cp1->pos_get+$match_pos);
				$cp1->copy($format_cp1);
				push @{$self->match_braces_fmt}, $format_cp1; 
				$cp1->format_append("<font_weight=bold>"); 
				$cp1->char_next(); 
				$cp1->format_append("</font_weight>");
				
				$cp2->char_prev(); 
				$cp2->copy($format_cp2);
				push @{$self->match_braces_fmt}, $format_cp2;
				$cp2->format_append("<font_weight=bold>"); 
				$cp2->char_next(); 
				$cp2->format_append("</font_weight>");
				
				last;
			}
			elsif ($search_pos == -1 && $match_pos != -1) {
				$depth--;
				$start = $match_pos+1;
				# problem: If match_pos == -1, then the loop never stops
				if ($start == (length($text)-1)) {
					$cp1->paragraph_next(); $cp1->paragraph_char_first();
					$text = $cp1->paragraph_text_get();
					$text = pEFL::Elm::Entry::markup_to_utf8($text);
					$text = Encode::decode("UTF-8",$text);
					
					
					$start = 0;
				}
			}
			else {
				$start = $match_pos < $search_pos ? $match_pos : $search_pos;
				$start++;
				$depth = $match_pos < $search_pos ? ($depth-1) : ($depth + 1);
			}
		}
		
	}
	
	$cp1->free();
	$cp2->free();
}

################################
# After change tab event the cursor must be set on the
# saved position
################################
sub text_set_done {
	my ($self, $entry) = @_;
	
	if ($self->is_change_tab() eq "yes") {
		my $pos = $self->app->current_tab->cursor_pos;
		$entry->cursor_pos_set($pos);
		$self->is_change_tab("no");
	}
	
 }

########################
# Fill undo stack
########################
sub fill_undo_stack {
	my ($self, $change_info, $change) = @_;
	
	my $current_tab = $self->app->current_tab();

	#use Data::Dumper;
	#print "CHANGE " . Dumper($change) . "\n";
	my @undo_stack = @{$current_tab->undo_stack};
	my $last_undo = $undo_stack[$#undo_stack];
	my $new_undo;
	
	
	if ($self->is_undo() eq "yes") {
		$self->is_undo("no");
		#my $insert_content = $change->{insert}->{content};
		# print "undo found $insert_content\n";
		
	}
	elsif ($self->undo_already_done() eq "yes") {
		$self->undo_already_done("no");
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
			my $prev_plain_length = $last_undo->{plain_length} || 0;
			my $prev_content = $last_undo->{content} || "";
			
			my $new_pos = $change->{insert}->{pos};
			#my $insert_content = $change->{insert}->{content};
			
			# Problem: In $change->{insert}->{plain_length} are \n = <br/>,
			# Tabs = <tab/> and umlauts &ouml;. Therefore the length is longer than utf8
			# with the following we correct plain length
			my $new_plain_length;
			my $insert_content_plain = $change->{insert}->{content};
			$new_plain_length = $change->{insert}->{plain_length};
			
			# Special case: <tab/> was replaced by filter
			# Undo record is already created 
			if ($insert_content_plain eq "\t" && $self->tabmode() eq "whitespaces" && $last_undo->{replaced_tab}) {
				
			}
			# Make a new undo record, only if a new word starts, a tab is inserted or a newline
			elsif ($prev_pos == ($new_pos - $prev_plain_length) && $insert_content_plain =~ m/\S/ && $insert_content_plain ne "\n" && $insert_content_plain ne "\t" ) {
				pop @{$current_tab->undo_stack};
				$new_undo->{pos} = $prev_pos;	
				$new_undo->{plain_length} = $prev_plain_length + $new_plain_length;
				$new_undo->{content} = $prev_content . $insert_content_plain;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			elsif (defined($insert_content_plain)) {
				$new_undo->{pos} = $new_pos;
				$new_undo->{content} = $insert_content_plain if (defined($insert_content_plain));
				$new_undo->{plain_length} = $new_plain_length;
				push @{$current_tab->undo_stack}, $new_undo;
			}
				
		}
		else {
			my $prev_start = $last_undo->{start} || 1;
			my $prev_content = $last_undo->{content} || "";
			my $prev_end = $last_undo->{end} || 1;
		
			my $start = $change->{del}->{start};
			my $end = $change->{del}->{end};
			
			# If user starts selection on the right, end would be the start position 
			# of the del event. This leads to problems at undo :-S
			# therefore let start always be the start position of the del event
			if ($end < $start) {
				my $tmp;
				$tmp = $start;
				$start = $end;
				$end = $tmp;
			}
			my $content_plain = $change->{del}->{content};
			
			# BackSlash key is pressed
			if ($last_undo->{del} && $prev_start == ($start +1) ) {
				pop @{$current_tab->undo_stack};
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $prev_end;
				$new_undo->{content} = $content_plain . $prev_content;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			# Delete key is pressed
			elsif ($last_undo->{del} && $prev_start == $start && $prev_end == $end) {
				pop @{$current_tab->undo_stack};
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $end;
				$new_undo->{content} = $prev_content . $content_plain;
				push @{$current_tab->undo_stack}, $new_undo;
			}
			# a new area is deleted
			else {
				$new_undo->{del} = 1;
				$new_undo->{start} = $start;
				$new_undo->{end} = $end;
				$new_undo->{content} = $content_plain;
				push @{$current_tab->undo_stack}, $new_undo;
			}
		
		}
	}
	
	#use Data::Dumper;
	#print "NEW UNDO " . Dumper($new_undo) . "\n\n";
	#print "UNDO STACK" . Dumper(@{$current_tab->undo_stack}) . "\n\n";
	return $new_undo;
}

sub undo {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	
	my $current_tab = $self->app->current_tab();
	
	#use Data::Dumper;
	#print "\n DO UNDO " . Dumper($current_tab->undo_stack) . "\n";
	
	my $undo = pop @{$current_tab->undo_stack};
	# print "CURSOR " . $entry->cursor_pos_get() . "\n";
	
	unless (defined($undo)) {
		return;
	}
	
	#use Data::Dumper;
	#print "\n DO UNDO " . Dumper($undo) . "\n";
	
	push @{$current_tab->redo_stack}, $undo;
	if ($undo->{del}) {
		# It seems that if one inserts withous selection
		# the event changed,user is not triggered
		# therefore here $self->is_undo("yes"); is not needed
		$entry->cursor_pos_set($undo->{start});
		my $content = $undo->{content};
		
		# $undo->{content} is already saved in utf8 format!!! Really???
		# $content = pEFL::Elm::Entry::utf8_to_markup($content);
		$content = pEFL::Elm::Entry::utf8_to_markup($content);
		
		$content =~ s/\t/<tab\/>/g; $content =~ s/\n/<br\/>/g;
		$entry->entry_insert($content);
		$entry->select_none();
		$self->rehighlight_and_retab_lines($undo);
		$entry->cursor_pos_set($undo->{end});
	}
	elsif ($undo->{pos} >= 0) {
		$self->is_undo("yes");
		
		#$entry->select_region_set($undo->{pos} - $undo->{plain_length}, $undo->{pos});
		my $text = $undo->{content}; #$text = pEFL::Elm::Entry::markup_to_utf8($text); decode_entities($text);
		$entry->select_region_set($undo->{pos}, $undo->{pos} + $undo->{plain_length});
		$entry->entry_insert("");
		$entry->select_none();
	}
	
}

sub redo {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	my $current_tab = $self->app->current_tab();
	
	#use Data::Dumper;
	#print "\n DO REDO " . Dumper($current_tab->redo_stack) . "\n";
	
	my $redo = pop @{$current_tab->redo_stack};
	return unless( defined($redo) );
	
	#use Data::Dumper;
	#print "\n DO REDO " . Dumper($redo) . "\n";
	
	push @{$current_tab->undo_stack}, $redo;
	
	if ($redo->{del}) {
		$self->is_undo("yes");
		
		# We cannot use $redo->{end} because if text with several chars was deleted 
		# with Delete Key it always is start+1. Therefore we must manually determine 
		# the length of the deleted content.
		# see https://github.com/MaxPerl/eSourceHighlight/issues/1
		# and perhaps https://github.com/MaxPerl/eSourceHighlight/issues/2 ?
		my $content_plain = pEFL::Elm::Entry::markup_to_utf8($redo->{content});
		$content_plain = Encode::decode("UTF-8",$content_plain); 
		
		my $length = length($content_plain);
		
		$entry->select_region_set($redo->{start},$redo->{start} + $length);
		
		$entry->entry_insert("");
	}
	elsif ($redo->{pos} >= 0) {
		# It seems that if one inserts withous selection
		# the event changed,user is not triggered
		# therefore here $self->is_undo("yes") is not needed 
		
		my $content = $redo->{content};
		
		# $redo->{content} is already saved in utf8 format!!!
		# $content = pEFL::Elm::Entry::markup_to_utf8($content);
		$content = pEFL::Elm::Entry::markup_to_utf8($content);
		
		$content =~ s/\t/<tab\/>/g; $content =~ s/\n/<br\/>/g;
		$entry->cursor_pos_set($redo->{pos});
		$entry->entry_insert($content);
		$self->rehighlight_and_retab_lines($redo); #, $redo;??
		$entry->cursor_pos_set($redo->{pos} + $redo->{plain_length});
	}

}


###########################
# Auto indent
##########################
sub auto_indent {
	my ($self,$entry,$change_info) = @_;
	
	my $new_cp = undef; 
	
	my $current_tab = $self->app->current_tab();
	my $change = $change_info->change();
	my $cursor_pos = $self->elm_entry->cursor_pos_get();
	
	my $content = "";
	
	my $textblock = $entry->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($cursor_pos);
	#my $cp1= $textblock->cursor_get(); 
	
	if ($change_info->insert()) {
		$content = $change->{insert}->{content};
	}
	
	if ($content eq "<br/>") {
		#$cp1->pos_set($entry->cursor_pos_get() );
		$cp1->paragraph_prev();
		$cp1->paragraph_char_first();
		my $text = $cp1->paragraph_text_get();
		 
		if ($text) {
			
			my $tabs = "";
			my $plain_length = 0; 
			if ($text =~ m/^<tab\/>/ || $text =~ m/^\s/) {
				
				while ($text =~ s/^ //) {
					$tabs = $tabs . " ";
					$plain_length++;
					#print "PLAIN LENGTH $plain_length\n";
				}
				
				while ($text =~ s/^<tab\/>//) {
					$tabs = $tabs . "<tab\/>";
					$plain_length++;
				}
				
			
			if ($tabs) {
				$cp1->pos_set($cursor_pos);
				$cp1->text_markup_prepend($tabs) ;
				$entry->calc_force();
				
				# Because there is no selection (?) the "change, MANUAL" event 
				# isn't triggered. Therefore we must push the undo stack manually
				my $auto_indent_undo = {
					content => $tabs,
					plain_length => $plain_length,
					pos => $cursor_pos,
				};
				
				push @{$current_tab->undo_stack}, $auto_indent_undo;
				
				$new_cp = $cp1->pos_get();
				}
			}
		}
	}
	
	$cp1->free();
	return $new_cp;
}

sub resize_tab_re {
	my $entry = shift; my $string = shift;
	# TODO: Copy the utf form from highlight_string
	my $utf8 = pEFL::Elm::Entry::markup_to_utf8($string);
	$utf8 = Encode::decode("UTF-8",$utf8);
	my $l = length($utf8);
	my $n;
	
	if ($l < $tabstop) {
		$n = $tabstop-$l;
	}
	else {
		$n = $l % $tabstop; 
		$n = $n == 0 ? $tabstop : $tabstop-$n;
	}
	# print "STR $utf8 L $l N $n\n"; 
	$n = $n*$entry->em();
	
	return "$string<tabstops=$n>"
}

sub resize_tabs {
	my $self = shift; my $content = shift;
	
	my @lines = split(/\n/,$content);
	
	# Save the last newlines
	my $newlines = "";
	while (chomp($content)) {
		$newlines = $newlines . "\n";
	}
	
	#use Data::Dumper;
	#$Data::Dumper::Terse = 1;
	#$Data::Dumper::Useqq = 1;
	#print "CONTENT " . Dumper($content) ."\n";
	#print "LINES " . Dumper(@lines) ."\n";
	my $new_content = "";
	my $i;
	for ($i=0; $i <= $#lines; $i++) {
			my $line  = $lines[$i];
		
			# harmonize tabs
			my $match = "([^\t]+)\t";
			$line =~ s!$match!resize_tab_re($self,$1)!ge;
			$new_content = $new_content . $line . "\n"; 
			$new_content = $new_content . $newlines if ($i == $#lines);
	}
	
	# Split added newline of last line
	$new_content =~ s/\n$//;
	#print "NEW CONTENT ". Dumper($new_content) . "\n\n";
		
	return $new_content;
	
}

sub highlight_resized_tabs {
	my ($entry,$content,$searchPattern) = @_;
	$content =~ s!$searchPattern!<tabstops=$1><tab\/><\/>!g;
	return $content;
}

sub resize_whitespaces_re {
	my ($utf8) = @_;
	
	return " " x $tabstop unless($utf8);
	my $l = length($utf8);
	my $n;
	
	if ($l < $tabstop) {
		$n = $tabstop-$l;
	}
	else {
		$n = $l % $tabstop; 
		$n = $n == 0 ? $tabstop : $tabstop-$n;
	}
	my $whitespace = " " x $n;
	return "$whitespace";
}

sub tabs_to_whitespaces {
	my ($entry, $en, $text) = @_;
	
	return $text unless ($entry->tabmode() eq "whitespaces");
	
	if ($text eq "<tab\/>") {
		my $textblock = $en->textblock_get();
		my $cp1 = pEFL::Evas::TextblockCursor->new($textblock); 
		my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
		
		$cp1->pos_set($en->cursor_pos_get()); 
		$cp1->paragraph_char_first();
		$cp2->pos_set($en->cursor_pos_get());
		
		my $line = $textblock->range_text_get($cp1,$cp2,EVAS_TEXTBLOCK_TEXT_PLAIN);
		$line = Encode::decode("UTF-8",$line);
		
		$line =~ m!([^\t]+)$!;
		
		$text = resize_whitespaces_re($1);
		
		$cp1->free(); $cp2->free();
		
		# Unfortunately the filter doesn't change the ChangeInfo
		# Therefore we create here the undo record and push it to 
		# the undo stack
		my $replaced_char_undo = {
			content => $text,
			plain_length => length($text),
			pos => $en->cursor_pos_get(),
			replaced_tab => 1,
		};
		my $current_tab = $entry->app->current_tab();
		push @{$current_tab->undo_stack}, $replaced_char_undo;
	}
	
	return $text;
}

sub tab_selection {
	my ($entry, $en) = @_;
	
		my ($start,$end) = $en->select_region_get();
		return unless($start && $end);
		
		my $textblock = $en->textblock_get();
		my $cp1 = pEFL::Evas::TextblockCursor->new($textblock); 
		my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
		
		$cp1->pos_set($start); 
		$cp1->paragraph_char_first();
		$cp2->pos_set($end);
		
		my $line = $textblock->range_text_get($cp1,$cp2,EVAS_TEXTBLOCK_TEXT_PLAIN);
		$line = Encode::decode("UTF-8",$line);
		
		my $text = "";
		foreach my $line (split($line,"\n")) {
		    $text = "\t".$line."\n";
		}
		
		$cp1->free(); $cp2->free();
		
		# Unfortunately the filter doesn't change the ChangeInfo
		# Therefore we create here the undo record and push it to 
		# the undo stack
		my $replaced_undo1 = {
			start => $start,
			end => $end,
			content => $line,
			del => 1
		};
		
		my $replaced_undo2 = {
			content => $text,
			plain_length => length($text),
			pos => $start,
			replaced_tab => 1,
		};
		
		my $current_tab = $entry->app->current_tab();
		push @{$current_tab->undo_stack}, $replaced_undo1;
		push @{$current_tab->undo_stack}, $replaced_undo2;
}



sub highlight_str {
	my $self = shift; my $text = shift;
	
	# Here we mustn't decode entities!!!!
	# Otherwise one can not input something like "<"
	# I hope this doesn't brings new problems :-S
	# but ö should no problem in entry....
	#decode_entities($text);
	
	$self->rehighlight("no");
	
	# Check whether there is a $sh_lang for the document
	my $sh_obj = $self->sh_obj; 
	my $sh_lm = $self->sh_langmap(); 
	my $sh_lang = $self->app->current_tab->sh_lang();
	
	
	if (defined($sh_lang) && $sh_lang =~ m/\.lang$/) {
		$text = $sh_obj->highlightString($text,$sh_lang);
	}
	elsif (defined($sh_lang)) {
		$text = $sh_obj->highlightString($text,$sh_lm->getMappedFileName($sh_lang));
	}
	# If there is no source highlight by the GNU source-highlight lib
	# we must encode HTML entities (otherwise it is done by source-highlight!!)
	else {
		encode_entities($text,"<>&");
	}
	
	return $text;
}

# Used by eSourceHighlight when opening a file
# and by eSourceHighlight::Settings when saving settings
sub rehighlight_all {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	
	#print "Set rehighlight no in rehighlight_all\n";
	#$self->rehighlight("no");
	
	my $cursor_pos = $entry->cursor_pos_get();
	
	
	my $text = $entry->entry_get();
	$text = pEFL::Elm::Entry::markup_to_utf8($text);
	$text = Encode::decode("UTF-8",$text);
	
	$text = $self->highlight_str($text);
	
	# Resize Tabs (TODO: Own function)
	$text = $self->resize_tabs($text) if ($text);
	$text = $self->highlight_resized_tabs($text, "<tabstops=(\\d*)>");
	$text =~ s/\n/<br\/>/g;$text =~ s/\t/<tab\/>/g;
	
	# if $entry->insert(undef|"") is called, then no "change" event is triggered
	# that means: $self->is_relight("yes") would apply also to the next change :-S
	# therefore check, whether there is a text
	if ($text) {

		#$self->is_rehighlight("yes");
		#$entry->select_all();
		$entry->entry_set($text);
		#$entry->entry_insert($text);
	}
	else {
		$self->rehighlight("yes");
	}
	
	$entry->select_none();
	$entry->cursor_pos_set($cursor_pos);

}

# $undo ist the item of the undo stack
sub get_rehighlight_lines {
	my ($self, $cp1, $cp2, $undo) = @_;
	
	
	if (defined($undo)) {
		if ($undo->{del}) {
			# if there is a del event then we relight from the line before 
			# the del event occured
			$cp1->pos_set($undo->{start});
			$cp1->paragraph_prev();
			$cp1->paragraph_char_first;
			
			# .. to the line after the del event
			$cp2->pos_set($undo->{end});
			$cp2->paragraph_next;$cp2->paragraph_next;
			# $cp2->paragraph_char_last;???? see under else...
			$cp2->line_char_last;
		}
		else {
				
			$cp1->pos_set($undo->{pos});
			$cp1->paragraph_prev();$cp1->paragraph_prev();
			$cp1->paragraph_char_first;
			
			$cp2->pos_set($undo->{pos}+$undo->{plain_length});
			$cp2->paragraph_next;$cp2->paragraph_next;
			# $cp2->paragraph_char_last;???? see under else...
			$cp2->line_char_last;
		}
	}
	else {
		# Otherwise we relight from the line before the actual cursor position...
		# !!!!!!! No, as in Editarea we rehighlight the visible range if cursor position changed
		# Therefore it should be enough to relight only the current line!!!!!!!!!!!!!
		#$cp1->paragraph_prev();
		$cp1->paragraph_char_first;
		
		# .. to the line after the actual cursor position :-)
		#$cp2->paragraph_next;
		$cp2->paragraph_char_last;
	}
	
	my $text = $cp1->range_text_get($cp2,EVAS_TEXTBLOCK_TEXT_PLAIN);
	$text = Encode::decode("UTF-8",$text);
	
	# Here we mustn't decode entities!!!!
	# Otherwise one can not input something like "<"
	# I hope this doesn't brings new problems :-S
	# but ö should no problem in entry....
	#decode_entities($text);
	
	return $text;
}
	
sub set_rehighlight_lines { 
	my ($self, $textblock, $cp1, $cp2, $text) = @_; 
	# if $entry->insert(undef|"") is called, then no "change" event is triggered
	# that means: $self->is_relight("yes") would apply also to the next change :-S
	# therefore check, whether there is a text
	if ($text) {
	
		$cp1->range_delete($cp2);
		$textblock->text_markup_prepend($cp1,$text);
	}

}

sub rehighlight_and_retab_lines {
	my ($self, $new_undo) = @_;
	
	my $entry = $self->elm_entry();
	my $current_tab = $self->app->current_tab();
	
	my $textblock = $entry->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($entry->cursor_pos_get());
	my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp2->pos_set($entry->cursor_pos_get());
	
	my $text = $self->get_rehighlight_lines($cp1,$cp2, $new_undo);
	my $mkp_text = $text;
	
	if ( $current_tab->source_highlight() eq "yes" ) {
		$mkp_text = $self->highlight_str($text);
	}
	
	#########################
	# resize and format tabs / format newlines
	########################
	$mkp_text = $self->resize_tabs($mkp_text) if ($mkp_text);
	$mkp_text = $self->highlight_resized_tabs($mkp_text, "<tabstops=(\\d*)>");
	
	
	$mkp_text =~ s/\n/<br\/>/g;$mkp_text =~ s/\t/<tab\/>/g;
	
	$self->set_rehighlight_lines($textblock,$cp1,$cp2,$mkp_text);
	$entry->calc_force;
	
	$cp1->free();
	$cp2->free();
}

sub clear_highlight {
	my ($self) = @_;
	
	my $entry = $self->elm_entry();
	my $cursor_pos = $entry->cursor_pos_get();
	my $text = $entry->entry_get();
	
	$text = $self->to_utf8($text);
	$text = $self->resize_tabs($text);
	
	$entry->entry_set($text);
}

sub to_utf8 {
	my ($self,$text) = @_;
	
	$text = pEFL::Elm::Entry::markup_to_utf8($text);
	
	$text = Encode::decode("UTF-8",$text);
	
	# We must encode the HTML entities.
	# Otherwise everything inside <.*> is deleted when entry is
	# set. Here it is about output of perl to Elm_Entry widget!!!
	encode_entities($text);
	
	$text =~ s/\n/<br\/>/g;$text =~ s/\t/<tab\/>/g;
	
	return $text;
}

sub column_get {
	my ($self) = @_;
	my $column;
	
	my $en = $self->elm_entry();
	
	my $textblock = $en->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($en->cursor_pos_get);
	my $cp2 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp2->pos_set($en->cursor_pos_get);
	$cp2->paragraph_char_first();
	
	$column = $cp1->pos_get() - $cp2->pos_get();
	
	$cp1->free();
	$cp2->free();
	
	return $column;
}

sub line_get {
	my ($self) = @_;
	
	my $en = $self->elm_entry();
	my $lines = 1;
	
	my $textblock = $en->textblock_get();
	my $cp1 = pEFL::Evas::TextblockCursor->new($textblock);
	$cp1->pos_set($en->cursor_pos_get);
	
	while ($cp1->paragraph_prev()) {
		$lines++;
	}
	
	$cp1->free();
		
	return $lines;
}

sub line_column_get {
	my ($self, $evas, $en, $e) = @_;
	my $column; my $lines;
	
	my $label = $self->app->elm_linecolumn_label();
	return unless(defined($label));
	
	$column = $self->column_get();
	
	my $keyname = $e->keyname();
	if ($keyname =~ m/Up|KP_Prior|Down|KP_Next|Return/ ) {
			$lines = $self->line_get();
	}
		
	
	if ($lines) {
		$label->text_set("Line: $lines Column: $column");
		$self->current_line($lines);
		$self->current_column($column);
	}
	else {
		my $text = $label->text_get();
		$text =~ s/(.*)Column:.*$/$1Column: $column/;
		$label->text_set($text);
		$self->current_column($column);
	}
	
}

sub line_column_get_mouse {
	my ($self, $evas, $en, $event) = @_;
	my $column; my $lines;
	
	my $label = $self->app->elm_linecolumn_label();
	return unless(defined($label));
	
	$column = $self->column_get();
	
	my $e = pEFL::ev_info2obj( $event, "pEFL::Evas::Event::MouseDown");
	my $mod = $e->modifiers();
	
	my $button = $e->button();
	if ($button == 1) {
		$lines = $self->line_get();
		
		_remove_match_braces($self,$en->textblock_get());
		$self->highlight_match_braces();
	
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
	
	if ($button == 1) {
		$self->rehighlight_visible_range() if ($self->app->current_tab->source_highlight() eq "yes" && !$mod->key_modifier_is_set("Shift"));
	}
	
}

sub get_line_on_del {
	my ($self, $change_info) = @_;
	
	unless ($change_info->insert) {
		my $change = $change_info->change();
		my $content = $change->{insert}->{content};
	
		if ($content eq "<br/>") {
			$self->set_linecolumn_label();
		}
	}
}

sub set_linecolumn_label {
	my ($self) = @_;
	
	my $line = $self->line_get();
	my $column = $self->column_get();
	my $label = $self->app->elm_linecolumn_label();
	return unless(defined($label));
	$label->text_set("Line: $line Column: $column");
	$self->current_line($line); 
}

######################
# Accessors 
#######################

sub AUTOLOAD {
	my ($self, $newval) = @_;
	
	die("No method $AUTOLOAD implemented\n")
		unless $AUTOLOAD =~m/is_undo|is_rehighlight|is_change_tab|is_open|highlight|rehighlight|current_line|current_column|match_braces|match_braces_fmt|paste|linewrap|autoindent|search|tabmode|sh_obj|sh_langmap|em|elm_entry|undo_processing|undo_already_done|/;
	
	my $attrib = $AUTOLOAD;
	$attrib =~ s/.*://;
	
	my $oldval = $self->{$attrib};
	$self->{$attrib} = $newval if defined($newval);
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

This is the Editor component of the Caecilia Appliation.

=head1 AUTHOR

Maximilian Lika, E<lt>maxperl@cpan.org<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2022 by Maximilian Lika

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.32.1 or,
at your option, any later version of Perl 5 you may have available.


=cut

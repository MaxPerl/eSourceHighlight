package eSourceHighlight;

use local::lib;

use 5.006001;
use strict;
use warnings;
use utf8;

use pEFL;
use pEFL::Elm;
use pEFL::Evas;
use pEFL::Ecore;

use File::ShareDir 'dist_dir';

use File::HomeDir;
use File::Basename;
use Cwd qw(abs_path getcwd);

use eSourceHighlight::Tab;
use eSourceHighlight::Tabs;
use eSourceHighlight::Entry;
use eSourceHighlight::Search;
use eSourceHighlight::Settings;

use Text::Tabs;

our $AUTOLOAD; 

require Exporter;

our @ISA = qw(Exporter);

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

our $SELF;

sub new {
	my ($class) = @_;
	our $share = dist_dir('eSourceHighlight');
	
	my $obj = {
		tabs => undef,
		entry => undef,
		current_tab => 0,
		settings => undef,
		share_dir => $share,
		elm_mainwindow => undef,
		elm_menu => undef,
		elm_searchbar => undef,
		elm_toolbar => undef,
		# Statusbar
		elm_doctype_label => undef,
		elm_src_highlight_check => undef,
		elm_linewrap_check => undef,
		elm_autoident_check => undef, 
		elm_match_braces_check => undef,
		elm_linecolumn_label => undef};
	bless($obj,$class);
	
	return $obj;
}

sub init_ui {
	my ($self) = @_;
	
	pEFL::Elm::init($#ARGV, \@ARGV);
	pEFL::Elm::Config::scroll_accel_factor_set(1);
	pEFL::Elm::policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
	my $win = pEFL::Elm::Win->util_standard_add("eSourceHighlight", "eSourceHighlight");
	$win->smart_callback_add("delete,request" => \&on_exit, $self);
	$self->elm_mainwindow($win);
	
	# Create new icon
	my $ic = pEFL::Elm::Icon->add($win);
	$ic->file_set($self->share_dir . "/icon1.svg", undef );
	$ic->size_hint_aspect_set(EVAS_ASPECT_CONTROL_VERTICAL, 1, 1);
	$win->icon_object_set($ic);
	
	# Create settings instance
	my $settings = eSourceHighlight::Settings->new($self);
	$self->settings($settings);
	
	my $config = $settings->load_config();
	$tabstop = $config->{tabstops} || 4; 
	
	my $box = pEFL::Elm::Box->add($win);
	$box->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$box->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$win->resize_object_add($box);
	$box->show();
	
	my $tabs = eSourceHighlight::Tabs->new($self,$box);
	$self->tabs($tabs);
	
	my $searchbar = pEFL::Elm::Box->new($box);
	$searchbar->horizontal_set(1);
	$searchbar->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$searchbar->size_hint_align_set(EVAS_HINT_FILL,0);
	$box->pack_end($searchbar);
	$searchbar->show();
	$self->elm_searchbar($searchbar);
	
	my $entry = eSourceHighlight::Entry->new($self,$box);
	$self->entry($entry);
	
	my $search = eSourceHighlight::Search->new($self,$searchbar);
	
	$self->add_menu($win,$box);
	
	$self->add_statusbar($box);
	
	if (@ARGV) {
	
		my $i = 0;
		foreach my $fname (@ARGV) {
			my $filename = abs_path($fname);
			$self->open_file($filename);
		}
	}
	else {
		my $tab = eSourceHighlight::Tab->new(filename => "", id => 0);
		$self->current_tab($tab);
		$self->tabs()->push_tab($tab);
	}
	
	$win->resize(900,600);
	$win->show();

	pEFL::Elm::run();
	pEFL::Elm::shutdown();
}


sub _button_click_cb {
	my ($data, $button, $event_info) = @_;
	my $item = $data->elm_toolbar_item;
	$item->del();
}


##################################
# Menu
##################################
sub add_menu {
	my ($self, $win, $box) = @_;
	
	my $menu = $win->main_menu_get();
	
	my $file_it = $menu->item_add(undef,undef,"File",undef, undef);
	
	$menu->item_add($file_it,"document-new","New",sub {$self->tabs->_new_tab_cb},undef);
	$menu->item_add($file_it,"document-open","Open",\&_open_cb,$self);
	$menu->item_add($file_it,"document-save","Save",\&save,$self);
	$menu->item_add($file_it,"document-save-as","Save as",\&save_as,$self);
	$menu->item_add($file_it,"document-close","Close current tab",\&_close_tab_cb,$self->tabs());
	$menu->item_add($file_it,"window-close","Exit",\&on_exit,$self);
	
	
	my $edit_it = $menu->item_add(undef,undef,"Edit",undef, undef);
	
	my $entry = $self->entry();
	$menu->item_add($edit_it,"edit-undo","Undo",\&eSourceHighlight::Entry::undo,$self->entry);
	$menu->item_add($edit_it,"edit-redo","Redo",\&eSourceHighlight::Entry::redo,$self->entry);
	$menu->item_add($edit_it,"edit-cut","Cut",sub {$self->entry->elm_entry->selection_cut()},undef);
	$menu->item_add($edit_it,"edit-copy","Copy",sub {$self->entry->elm_entry->selection_copy()},undef);
	$menu->item_add($edit_it,"edit-paste","Paste",sub {$self->entry->elm_entry->selection_paste()},undef);
	$menu->item_add($edit_it,"edit-find","Find / Replace",\&toggle_find,$self);
	$menu->item_add($edit_it,"preferences-other","Settings",sub {my $s = $self->settings(); $s->show_dialog($self)},undef);
	
	my $doc_it = $menu->item_add(undef,undef,"Document",undef, undef);
	my $linewrap_check = pEFL::Elm::Check->add($menu); $linewrap_check->state_set(1); 
	my $linewrap_it = $menu->item_add($doc_it,"document-new","Line wrap",\&toggle_linewrap,$self);
	$linewrap_it->content_set($linewrap_check);
	$self->elm_linewrap_check($linewrap_check);

	my $autoident_check = pEFL::Elm::Check->add($menu); $autoident_check->state_set(1); 
	my $autoident_it = $menu->item_add($doc_it,"document-new","Autoident",\&toggle_autoident,$self);
	$autoident_it->content_set($autoident_check);
	$self->elm_autoident_check($autoident_check);
	
	my $match_braces_check = pEFL::Elm::Check->add($menu); $match_braces_check->state_set(1); 
	my $match_braces_it = $menu->item_add($doc_it,"document-new","Highlight match braces",\&toggle_match_braces,$self);
	$match_braces_it->content_set($match_braces_check);
	$self->elm_match_braces_check($match_braces_check);
	
	my $src_highlight_check = pEFL::Elm::Check->add($menu); $src_highlight_check->state_set(1); 
	my $src_highlight_it = $menu->item_add($doc_it,"document-new","Source highlight",\&toggle_src_highlight,$self);
	$src_highlight_it->content_set($src_highlight_check);
	$self->elm_src_highlight_check($src_highlight_check);
	
	my $help_it = $menu->item_add(undef,undef,"Help",undef, undef);
	my $about_it = $menu->item_add($help_it,"help-about","About",\&about,$self);
	# Create new icon
	my $ic = pEFL::Elm::Icon->add($win);
	$ic->file_set($self->share_dir . "/icon1.svg", undef );
	$ic->size_hint_aspect_set(EVAS_ASPECT_CONTROL_VERTICAL, 1, 1);
	$about_it->content_set($ic);
	
	my $src_format_it = $menu->item_add($doc_it,undef,"Set source format",\&set_src_format,$self);
	my $rehighlight_format_it = $menu->item_add($doc_it,undef,"Rehighlight all",sub {$self->entry->rehighlight_all()},$self);
	
	# Keyboard shortcuts
	pEFL::Ecore::EventHandler->add(ECORE_EVENT_KEY_DOWN, \&key_down, $self);
}

sub set_src_format {
	my ($self) = (@_);
	
	my $src_win = pEFL::Elm::Win->add($self->elm_mainwindow(), "Open a file", ELM_WIN_BASIC);
	$src_win->focus_highlight_enabled_set(1);
	$src_win->autodel_set(1);
	
	my $bx = pEFL::Elm::Box->add($src_win);
	$bx->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$bx->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$bx->show();
	
	my $list = pEFL::Elm::Genlist->new($bx);
	$list->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$list->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$list->show();
	
	my $itc = pEFL::Elm::GenlistItemClass->new();
	$itc->item_style("default");
	$itc->text_get(\&src_genlist_text_get);
	
	my $lm = $self->entry->sh_langmap();
	$lm->getMappedFileName("perl") ;
	my $langs = $lm->getLangNames();
	my @langs = @$langs;
	
	
	foreach my $lang (@langs) {
		$list->item_append($itc,$lang, undef, ELM_GENLIST_ITEM_NONE(), \&_select_src_highlight, $self); 
	}
	
	my $btn = pEFL::Elm::Button->add($bx);
	$btn->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$btn->size_hint_align_set(EVAS_HINT_FILL,0);
	$btn->text_set("Cancel");
	$btn->smart_callback_add("clicked" => sub {$src_win->del()}, undef);
	$btn->show();
	
	$bx->pack_end($list);
	$bx->pack_end($btn);

	$src_win->resize_object_add($bx);
	$src_win->resize(250,200);
	
	$src_win->show();
	
	return $src_win;
}

sub _select_src_highlight {
	my ($self, $obj, $item) = @_;
	$item = pEFL::ev_info2obj($item,"ElmGenlistItemPtr");
	
	my $src_win = $obj->top_widget_get;
	
	my $lang = $item->text_get();
	my $tab = $self->current_tab();
	$tab->sh_lang($lang);
	
	$self->change_doctype_label();
	
	$self->entry->rehighlight_all() if ($tab->source_highlight() eq "yes");
	
	$src_win->del();
}

sub src_genlist_text_get {
	my ($data, $obj, $part) = @_;
	return "$data";
}

sub key_down {
	my ($self, $type, $event) = @_;
	my $e = pEFL::ev_info2obj($event, "pEFL::Ecore::Event::Key");
	my $keyname = $e->keyname();
	my $modifiers = $e->modifiers();
	
	if ($modifiers == 2 && $keyname eq "n") {
		$self->tabs->_new_tab_cb();
	}
	elsif ($modifiers == 2 && $keyname eq "o") {
		_open_cb($self);
	}
	elsif ($modifiers == 2 && $keyname eq "s") {
		save($self);
	}
	elsif ($modifiers == 3 && $keyname eq "s") {
		save_as($self);
	}
	elsif ($modifiers == 2 && $keyname eq "w") {
		_close_tab_cb($self->tabs);
	}
	elsif ($modifiers == 2 && $keyname eq "q") {
		on_exit($self);
	}
	elsif ($modifiers == 2 && $keyname eq "z") {
		eSourceHighlight::Entry::undo($self->entry);
	}
	elsif ($modifiers == 2 && $keyname eq "y") {
		eSourceHighlight::Entry::redo($self->entry);
	}
	elsif ($modifiers == 2 && $keyname eq "f") {
		my $search = $self->entry->search();
		my $widget = $search->elm_widget();
		my $entry = $self->entry->elm_entry();
		
		my $text = $entry->selection_get();
		$text = pEFL::Elm::Entry::markup_to_utf8($text);
		$text = Encode::decode("UTF-8",$text);
		
		if ($widget->visible_get()) {
			$search->elm_entry->focus_set(1);
			$search->elm_entry->entry_set($text) if ($text);
			$search->elm_entry->select_all();
		}
		else {
			$self->toggle_find();
			if ($text) {
				$search->elm_entry->entry_set($text);
				$search->elm_entry->select_all();
			}
		}
	}
	elsif ($modifiers == 2 && $keyname eq "r") {
		my $search = $self->entry->search();
		my $widget = $search->elm_widget();
		my $entry = $self->entry->elm_entry();
		
		my $text = $entry->selection_get();
		$text = pEFL::Elm::Entry::markup_to_utf8($text);
		$text = Encode::decode("UTF-8",$text);
		
		
		if ($widget->visible_get()) {
			$search->elm_entry->focus_set(1);
			$search->elm_entry->entry_set($text) if ($text);
			$search->elm_entry->select_all();
		}
		else {
			$self->toggle_find();
			if ($text) {
				$search->elm_entry->entry_set($text);
				$search->elm_entry->select_all();
			}
		}
	}
} 

sub on_exit {
	my ($self) = @_;
	
	my @unsaved = grep $_->changed() > 0, @{$self->tabs->tabs()};
	
	if (@unsaved) {
		my $popup = pEFL::Elm::Popup->add($self->elm_mainwindow());
		
		$popup->part_text_set("default","Warning: There are some unsaved files. Close anyway?");
		
		my $btn1 = pEFL::Elm::Button->add($popup);
		$btn1->text_set("Okay");
		$btn1->smart_callback_add("clicked" => sub {pEFL::Elm::exit});
		
		my $btn2 = pEFL::Elm::Button->add($popup);
		$btn2->text_set("Cancel");
		$btn2->smart_callback_add("clicked" => sub {$popup->del});
		
		$popup->part_content_set("button1", $btn1);
		$popup->part_content_set("button2", $btn2);
		
		$popup->show();
	}
	else {
		pEFL::Elm::exit();
	}
}



sub file_cb {
	my ($self) = @_;
	
	my $fs_win = pEFL::Elm::Win->add($self->elm_mainwindow(), "Open a file", ELM_WIN_BASIC);
	$fs_win->focus_highlight_enabled_set(1);
	$fs_win->autodel_set(1);
	
	my $vbox = pEFL::Elm::Box->add($fs_win);
	$vbox->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$vbox->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$vbox->show();
	$fs_win->resize_object_add($vbox);
	
	my $fs = pEFL::Elm::Fileselector->add($fs_win);
	
	my $path; my $filename;
	if ($self->current_tab->filename) { 
		(undef, $path, undef) = fileparse( $self->current_tab->filename );
		$filename = $self->current_tab->filename;
	}
	else { 
		$path = getcwd || File::HomeDir->my_home;
	}
	$fs->path_set($path);
	$fs->selected_set($filename) if ($filename);
	$fs->expandable_set(0);
	$fs->expandable_set(0);
	$fs->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$fs->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$fs->show();
	
	$vbox->pack_end($fs);
	#$fs_win->resize_object_add($fs);
	$fs_win->resize(600,400);
	$fs_win->show();
	
	return $fs;
}

sub about {
	my ($self) = @_;
	
	my $popup = pEFL::Elm::Popup->add($self->elm_mainwindow());
	$popup->text_set("<b>eSourceHighlight</b><br/><br/>A simple frontend for the GNU source-highlight library written in Perl/pEFL");
	
	# popup buttons
	my $btn = pEFL::Elm::Button->add($popup);
	$btn->text_set("Close");
	$popup->part_content_set("button1",$btn);
	$btn->smart_callback_add("clicked",sub {$_[0]->del},$popup);
	
	# popup show should be called after adding all the contents and the buttons
	# of popup to set the focus into popup's contents correctly.
	$popup->show();
	
}

sub _open_cb {
	my ($self) = @_;
	
	my $fs = $self->file_cb;
	
	$fs->smart_callback_add("done", \&_fs_open_done, $self);
	$fs->smart_callback_add("activated", \&_fs_open_done, $self);
	$fs->smart_callback_add("selected,invalid", \&_fs_invalid, $self);
}

sub save_as {
	my ($self) = @_;
	
	my $fs = $self->file_cb;
	
	$fs->is_save_set(1);
	$fs->smart_callback_add("done", \&_fs_save_done, $self);
	$fs->smart_callback_add("activated", \&_fs_save_done, $self);
	$fs->smart_callback_add("selected,invalid", \&_fs_invalid, $self);
}

sub save {
	my ($self) = @_;
	
	my $current_tab = $self->current_tab();
	my $elm_it = $current_tab->elm_toolbar_item();
	my $en = $self->entry->elm_entry();
	my $filename = $current_tab->filename || "";
	
	if ($filename) {
		# get the content of the buffer, without hidden characters
		my $content = $en->entry_get();
		$content = pEFL::Elm::Entry::markup_to_utf8($content);
		
		# umlauts etc. must be converted
		$content = Encode::decode("utf-8",$content);
		
		# Here we mustn't decode entities
		# otherwise for example &lt; is saved as <
		#decode_entities($content);
		
		
		open my $fh, ">:encoding(UTF-8)", $filename or die "Could not save file: $filename\n";
		print $fh "$content";
		close $fh;
		
		$current_tab->changed(0);
		my ($name,$dirs,$suffix) = fileparse($filename); 
		$elm_it->part_text_set("default",$name);
	}
	else {
		# use save_as_callback
		$self->save_as();
	}
	
}

sub _fs_invalid {
	my ($self, $obj, $ev_info) = @_;
	print "Warn: File doesn't exist\n";
}

sub _fs_save_done {
	my ($self, $obj, $ev_info) = @_;
	
	my $selected = pEFL::ev_info2s($ev_info);
	
	my $fs_win = $obj->top_widget_get;
	$fs_win->del();
	
	return unless($selected);
	
	my $current_tab = $self->current_tab();
	$current_tab->filename($selected);
	
	$self->save();
}


sub open_file {
	my ($self, $selected) = @_;
	
	my $config = $self->settings->load_config();
	
	if (-e $selected && -f $selected && -r $selected) {
		
		my $en = $self->entry->elm_entry();
		
		# Open file
		open my $fh, "<:encoding(utf-8)", $selected;
		my $content=""; my $line;
		while (my $line=<$fh>) {
			$content = $content . $line;
		}
	
		close $fh;
		
		if ($config->{expand_tabs}) {
			$content = expand($content);	
		}
		elsif ($config->{unexpand_tabs}) {
			$content = unexpand($content);
		}
		
		$content = pEFL::Elm::Entry::utf8_to_markup($content);
		
		# Change the filename variable and/or open a new tab
		my ($name,$dirs,$suffix) = fileparse($selected); 
		
		my $tab = $self->current_tab();
		
		if ( (scalar(@{$self->tabs->tabs}) == 1) && (!$tab->filename) && ($tab->id == 0) && ($tab->changed() == 0)) { 
			$tab->filename($selected);
		}
		else {
			if ($tab) {
				$tab->content($en->entry_get);
				$tab->cursor_pos($en->cursor_pos_get());
			}
			
			my $new_tab = eSourceHighlight::Tab->new(filename => $selected, id => scalar( @{$self->tabs->tabs} ) );
			$self->current_tab($new_tab);
			$self->tabs()->push_tab($new_tab);
		}
	
		# change content of the entry
		
		# This seems to be already done by pEFL::Elm::Entry::utf8_to_markup
		#$content =~ s/\t/<tab\/>/g;
		#$content =~ s/\n/<br\/>/g;
		$en->entry_set($content);

		# Determ the input language 
		$self->entry->determ_source_lang($selected);
		$self->change_doctype_label();	
		
		#rehighlight all
		$self->entry->rehighlight_all();
		
		# Workaround: Through inserting changed event is triggered
		$self->current_tab->changed(0);
		$self->current_tab->elm_toolbar_item->text_set($name);
		
		$en->cursor_pos_set(0);
	}
	else {
		warn "Could not open file $selected\n";
	}
}

sub _fs_open_done {
	my ($self, $obj, $ev_info) = @_;
	
	my $fs_win = $obj->top_widget_get;
	$fs_win->del();
	
	return unless($ev_info);
	
	my $selected = pEFL::ev_info2s($ev_info);
	
	$self->open_file($selected);
	
}



sub toggle_find {
	my ($self, $obj, $event) = @_;
	
	my $widget = $self->entry->search->elm_widget();
	my $searchbar = $self->elm_searchbar();
	
	if ($widget->visible_get()) {
		$widget->hide();
		$searchbar->unpack_all();
	}
	else {
		$widget->show();
		$searchbar->pack_end($widget);
		$widget->focus_set(1);
		#$searchbar->show();
	}
}

sub toggle_linewrap {
	my ($self, $obj, $ev) = @_;
	my $check = $self->elm_linewrap_check();
	
	my $entry = $self->entry();
	
	if ($entry->linewrap() eq "yes") {
		$entry->linewrap("no");
		$entry->elm_entry()->line_wrap_set(ELM_WRAP_NONE);
		
		$check->state_set(0);
	}
	else {
		$entry->linewrap("yes");
		$entry->elm_entry()->line_wrap_set(ELM_WRAP_WORD);
		
		$check->state_set(1);
	}
}

sub toggle_autoident {
	my ($self, $obj, $ev) = @_;
	my $check = $self->elm_autoident_check();
	
	my $entry = $self->entry();
	
	if ($entry->autoindent() eq "yes") {
		$entry->autoindent("no");
		$check->state_set(0);
	}
	else {
		$entry->autoindent("yes");
		$check->state_set(1);
	}
}


sub toggle_match_braces {
	my ($self, $obj, $ev) = @_;
	my $check = $self->elm_match_braces_check();
	
	my $entry = $self->entry();
	
	if ($entry->match_braces() eq "yes") {
		$entry->match_braces("no");
		$check->state_set(0);
	}
	else {
		$entry->match_braces("yes");
		$check->state_set(1);
	}
}

sub change_doctype_options {
	my ($self) = @_;
	
	my $current_tab = $self->current_tab();
	
	my $check = $self->elm_src_highlight_check();
	return unless($check);
	
	if ($current_tab->source_highlight() eq "yes") {
		$check->state_set(1);
	}
	else {
		$check->state_set(0);
	}
	
}

sub change_doctype_label {
	my ($self) = @_;
	my $entry = $self->current_tab();
	my $doctype = $entry->sh_lang() || "Unknown"; $doctype =~ s/\.lang$//;
	my $doctype_label = $self->elm_doctype_label(); 
	$doctype_label->text_set("Document Type: $doctype") if (defined($doctype_label));
}

sub toggle_src_highlight {
	my ($self, $obj, $ev) = @_;
	my $check = $self->elm_src_highlight_check();
	
	my $current_tab = $self->current_tab();
	
	if ($current_tab->source_highlight() eq "yes") {
		$current_tab->source_highlight("no");
		$self->entry->clear_highlight();
		
		$check->state_set(0);
	}
	else {
		$current_tab->source_highlight("yes");
		$self->entry->rehighlight_all();
		
		$check->state_set(1);
	}
}

#################################
# Status Bar
##############################

sub add_statusbar {
	my ($self,$vbox) = @_;
	
	my $hbox = pEFL::Elm::Box->add($vbox);
	$hbox->padding_set(25,25);
	$hbox->horizontal_set(1);
	$hbox->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$hbox->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$vbox->pack_end($hbox);
	$hbox->show();
	
	my $separator = pEFL::Elm::Separator->add($hbox);
	$separator->horizontal_set(1);
	$separator->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$separator->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$hbox->pack_end($separator);
	$separator->show();
	
	my $doctype_label = pEFL::Elm::Label->add($hbox);
	$doctype_label->text_set("Document Type: Unknown");
	$doctype_label->show(); 
	$hbox->pack_end($doctype_label);
	$self->elm_doctype_label($doctype_label);
	
	my $separator2 = pEFL::Elm::Separator->add($hbox);
	$separator2->horizontal_set(1);
	$hbox->pack_end($separator2);
	$separator2->show();
	
	my $line_column_label = pEFL::Elm::Label->add($hbox);
	$line_column_label->text_set("Line: 1 Column: 0");
	$line_column_label->show(); 
	$hbox->pack_end($line_column_label);
	$self->elm_linecolumn_label($line_column_label);
	
	my $separator3 = pEFL::Elm::Separator->add($hbox);
	$separator3->horizontal_set(1);
	$hbox->pack_end($separator3);
	$separator3->show();
}

######################
# Accessors 
#######################

sub AUTOLOAD {
	my ($self, $newval) = @_;
	
	die("No method $AUTOLOAD implemented\n")
		unless $AUTOLOAD =~ m/tabs|entry|settings|share_dir|current_tab|elm_mainwindow|elm_menu|elm_toolbar|elm_searchbar|elm_doctype_label|elm_src_highlight_check|elm_linewrap_check|elm_autoident_check|elm_match_braces_check|elm_linecolumn_label/;
	
	my $attrib = $AUTOLOAD;
	$attrib =~ s/.*://;
	
	my $oldval = $self->{$attrib};
	$self->{$attrib} = $newval if $newval;
	
	return $oldval;
}

sub DESTROY {

}


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

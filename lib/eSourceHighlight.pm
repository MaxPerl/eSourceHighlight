package eSourceHighlight;

use local::lib;

use 5.006001;
use strict;
use warnings;
use utf8;

use Efl;
use Efl::Elm;
use Efl::Evas;
use Efl::Ecore;
use Efl::Ecore::EventHandler;
use Efl::Ecore::Event::Key;
use Efl::Elm::Config;

use File::ShareDir 'dist_dir';

use File::HomeDir;
use File::Basename;
use Cwd qw(abs_path getcwd);

use eSourceHighlight::Tab;
use eSourceHighlight::Entry;
use eSourceHighlight::Search;

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
		tabs => [],
		entry => undef,
		current_tab => 0,
		share_dir => $share,
		elm_mainwindow => undef,
		elm_menu => undef,
		elm_searchbar => undef,
		elm_toolbar => undef,
		elm_tabsbar => undef,
		# Statusbar
		elm_doctype_label => undef,
		elm_src_highlight_check => undef,
		elm_linewrap_check => undef,
		elm_autoident_check => undef, 
		elm_linecolumn_label => undef};
	bless($obj,$class);
	
	return $obj;
}

sub init_ui {
	my ($self) = @_;
	
	Efl::Elm::init($#ARGV, \@ARGV);
	Efl::Elm::Config::scroll_accel_factor_set(1);
	Efl::Elm::policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
	my $win = Efl::Elm::Win->util_standard_add("eSourceHighlight", "eSourceHighlight");
	$win->smart_callback_add("delete,request" => \&on_exit, $self);
	$self->elm_mainwindow($win);
	
	# Create new icon
	my $ic = Efl::Elm::Icon->add($win);
	$ic->file_set($self->share_dir . "/icon1.svg", undef );
	$ic->size_hint_aspect_set(EVAS_ASPECT_CONTROL_VERTICAL, 1, 1);
	$win->icon_object_set($ic);
		
	my $box = Efl::Elm::Box->add($win);
	$box->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$box->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$win->resize_object_add($box);
	$box->show();
	
	 
	init_tabsbar($self,$box);
	
	my $searchbar = Efl::Elm::Box->new($box);
	$searchbar->horizontal_set(1);
	$searchbar->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$searchbar->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
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
		$self->push_tab($tab);
	}
	
	$win->resize(900,600);
	$win->show();

	Efl::Elm::run();
	Efl::Elm::shutdown();
}

sub init_tabsbar {
	my ($self, $box) = @_;
	my $tabsbar = Efl::Elm::Toolbar->add($box);
	#$tabsbar->always_select_mode_set(1);
	#$tabsbar->no_select_mode_set(1);
	$tabsbar->homogeneous_set(1);
	
	$tabsbar->align_set(0);
   	$tabsbar->size_hint_align_set(EVAS_HINT_FILL, EVAS_HINT_FILL);
   	$tabsbar->size_hint_weight_set(EVAS_HINT_EXPAND, 0);
	
	$self->elm_tabsbar($tabsbar);
	$tabsbar->shrink_mode_set(ELM_TOOLBAR_SHRINK_SCROLL);
	$tabsbar->transverse_expanded_set(1);
	$box->pack_end($tabsbar);
	
	# This is very tricky
	# _close_tab_cb only works if the right tab is selected
	# the easiest solution would be to make an own menu for each toolbar item
	# unfortunately this does not work (because items can not have own evas (smart) events
	# therefore the solution here is only to show the menu when a left click occurs at the
	# selected tab item (see show_tab_menu)
	my $menu = Efl::Elm::Menu->add($tabsbar);
	$menu->item_add(undef,undef,"Close tab",\&_close_tab_cb,$self);
	$tabsbar->event_callback_add(EVAS_CALLBACK_MOUSE_DOWN,\&show_tab_menu,$menu);
	$tabsbar->smart_callback_add("unselected",\&_no_change_tab,$self);

	$tabsbar->show();
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
	
	$menu->item_add($file_it,"document-new","New",\&_new_tab_cb,$self);
	$menu->item_add($file_it,"document-open","Open",\&_open_cb,$self);
	$menu->item_add($file_it,"document-save","Save",\&save,$self);
	$menu->item_add($file_it,"document-save-as","Save as",\&save_as,$self);
	$menu->item_add($file_it,"document-close","Close current tab",\&_close_tab_cb,$self);
	$menu->item_add($file_it,"window-close","Exit",\&on_exit,$self);
	
	
	my $edit_it = $menu->item_add(undef,undef,"Edit",undef, undef);
	
	my $entry = $self->entry();
	$menu->item_add($edit_it,"edit-undo","Undo",\&eSourceHighlight::Entry::undo,$self->entry);
	$menu->item_add($edit_it,"edit-redo","Redo",\&eSourceHighlight::Entry::redo,$self->entry);
	$menu->item_add($edit_it,"edit-cut","Cut",sub {$self->entry->elm_entry->selection_cut()},undef);
	$menu->item_add($edit_it,"edit-copy","Copy",sub {$self->entry->elm_entry->selection_copy()},undef);
	$menu->item_add($edit_it,"edit-paste","Paste",sub {$self->entry->elm_entry->selection_paste()},undef);
	$menu->item_add($edit_it,"edit-find","Find / Replace",\&toggle_find,$self);
	
	my $doc_it = $menu->item_add(undef,undef,"Document",undef, undef);
	my $linewrap_check = Efl::Elm::Check->add($menu); $linewrap_check->state_set(1); 
	my $linewrap_it = $menu->item_add($doc_it,"document-new","Line wrap",\&toggle_linewrap,$self);
	$linewrap_it->content_set($linewrap_check);
	$self->elm_linewrap_check($linewrap_check);

	my $autoident_check = Efl::Elm::Check->add($menu); $autoident_check->state_set(1); 
	my $autoident_it = $menu->item_add($doc_it,"document-new","Autoident",\&toggle_autoident,$self);
	$autoident_it->content_set($autoident_check);
	$self->elm_autoident_check($autoident_check);
	
	my $src_highlight_check = Efl::Elm::Check->add($menu); $src_highlight_check->state_set(1); 
	my $src_highlight_it = $menu->item_add($doc_it,"document-new","Source highlight",\&toggle_src_highlight,$self);
	$src_highlight_it->content_set($src_highlight_check);
	$self->elm_src_highlight_check($src_highlight_check);
	
	my $help_it = $menu->item_add(undef,undef,"Help",undef, undef);
	my $about_it = $menu->item_add($help_it,"help-about","About",\&about,$self);
	# Create new icon
	my $ic = Efl::Elm::Icon->add($win);
	$ic->file_set($self->share_dir . "/icon1.svg", undef );
	$ic->size_hint_aspect_set(EVAS_ASPECT_CONTROL_VERTICAL, 1, 1);
	$about_it->content_set($ic);
	
	my $src_format_it = $menu->item_add($doc_it,undef,"Set source format",\&set_src_format,$self);
	
	# Keyboard shortcuts
	Efl::Ecore::EventHandler->add(ECORE_EVENT_KEY_DOWN, \&key_down, $self);
}

sub set_src_format {
	my ($self) = (@_);
	
	my $src_win = Efl::Elm::Win->add($self->elm_mainwindow(), "Open a file", ELM_WIN_BASIC);
	$src_win->focus_highlight_enabled_set(1);
	$src_win->autodel_set(1);
	
	my $bx = Efl::Elm::Box->add($src_win);
	$bx->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$bx->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$bx->show();
	
	my $list = Efl::Elm::Genlist->new($bx);
	$list->size_hint_weight_set(EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
	$list->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$list->show();
	
	my $itc = Efl::Elm::GenlistItemClass->new();
	$itc->item_style("default");
	$itc->text_get(\&src_genlist_text_get);
	
	my $lm = $self->entry->sh_langmap();
	$lm->getMappedFileName("perl") ;
	my $langs = $lm->getLangNames();
	my @langs = @$langs;
	
	
	foreach my $lang (@langs) {
		$list->item_append($itc,$lang, undef, ELM_GENLIST_ITEM_NONE(), \&_select_src_highlight, $self);	
	}
	
	my $btn = Efl::Elm::Button->add($bx);
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
	$item = Efl::ev_info2obj($item,"ElmGenlistItemPtr");
	
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
	#print "LABEL $data\n";
	return "$data";
}

sub key_down {
	my ($self, $type, $event) = @_;
	my $e = Efl::ev_info2obj($event, "Efl::Ecore::Event::Key");
	my $keyname = $e->keyname();
	my $modifiers = $e->modifiers();
	
	if ($modifiers == 2 && $keyname eq "n") {
		_new_tab_cb($self);
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
		_close_tab_cb($self);
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
		if ($widget->visible_get()) {
			$search->elm_entry->focus_set(1);
			$search->elm_entry->select_all();
		}
		else {
			$self->toggle_find();
		}
	}
	elsif ($modifiers == 2 && $keyname eq "r") {
		my $search = $self->entry->search();
		my $widget = $search->elm_widget();
		if ($widget->visible_get()) {
			$search->elm_replace_entry->focus_set(1);
			$search->elm_replace_entry->select_all();
		}
		else {
			$self->toggle_find();
		}
	}
} 

sub on_exit {
	my ($self) = @_;
	
	my @unsaved = grep $_->changed() > 0, @{$self->tabs()};
	
	if (@unsaved) {
		my $popup = Efl::Elm::Popup->add($self->elm_mainwindow());
		
		$popup->part_text_set("default","Warning: There are some unsaved files. Close anyway?");
		
		my $btn1 = Efl::Elm::Button->add($popup);
		$btn1->text_set("Okay");
		$btn1->smart_callback_add("clicked" => sub {Efl::Elm::exit});
		
		my $btn2 = Efl::Elm::Button->add($popup);
		$btn2->text_set("Cancel");
		$btn2->smart_callback_add("clicked" => sub {$popup->del});
		
		$popup->part_content_set("button1", $btn1);
		$popup->part_content_set("button2", $btn2);
		
		$popup->show();
	}
	else {
		Efl::Elm::exit();
	}
}

sub _new_tab_cb {
	my ($self) = @_;
	my @tabs = @{$self->tabs};
	my $tab_id = $#tabs+1;
	my $tab = eSourceHighlight::Tab->new(id => $tab_id);
	$self->push_tab($tab);
}

sub file_cb {
	my ($self) = @_;
	
	my $fs_win = Efl::Elm::Win->add($self->elm_mainwindow(), "Open a file", ELM_WIN_BASIC);
	$fs_win->focus_highlight_enabled_set(1);
	$fs_win->autodel_set(1);
	
	my $vbox = Efl::Elm::Box->add($fs_win);
	$vbox->size_hint_weight_set(EVAS_HINT_EXPAND,EVAS_HINT_EXPAND);
	$vbox->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$vbox->show();
	$fs_win->resize_object_add($vbox);
	
	my $fs = Efl::Elm::Fileselector->add($fs_win);
	
	my $path; 
	if ($self->current_tab->filename) { 
		(undef, $path, undef) = fileparse( $self->current_tab->filename );
	}
	else { 
		$path = getcwd || File::HomeDir->my_home;
	}
	$fs->path_set($path);
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
	
	my $popup = Efl::Elm::Popup->add($self->elm_mainwindow());
	$popup->text_set("<b>eSourceHighlight</b><br/><br/>A simple frontend for the GNU source-highlight library written in Perl/Efl");
	
	# popup buttons
	my $btn = Efl::Elm::Button->add($popup);
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
		$content = Efl::Elm::Entry::markup_to_utf8($content);
		
		open my $fh, ">:encoding(utf8)", $filename or die "Could not save file: $filename\n";
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
	
	my $selected = Efl::ev_info2s($ev_info);
	
	my $fs_win = $obj->top_widget_get;
	$fs_win->del();
	
	return unless($selected);
	
	my $current_tab = $self->current_tab();
	$current_tab->filename($selected);
	
	$self->save();
}

sub open_file {
	my ($self, $selected) = @_;
	
	if (-e $selected && -f $selected && -r $selected) {
		
		my $en = $self->entry->elm_entry();
		
		# Open file
		open my $fh, "<:encoding(utf-8)", $selected;
		my $content="";
		while (my $line=<$fh>) {
			$content = $content . $line;
		}
		
		$content = Efl::Elm::Entry::utf8_to_markup($content);
		
		# Change the filename variable and/or open a new tab
		my ($name,$dirs,$suffix) = fileparse($selected); 
		
		my $tab = $self->current_tab();
		
		if ( (scalar(@{$self->tabs}) == 1) && (!$tab->filename) && ($tab->id == 0) && ($tab->changed() == 0)) { 
			$tab->filename($selected);
		}
		else {
		 	if ($tab) {
		 		$tab->content($en->entry_get);
		 		$tab->cursor_pos($en->cursor_pos_get());
		 	}
			
			my $new_tab = eSourceHighlight::Tab->new(filename => $selected, id => scalar( @{$self->tabs} ) );
			$self->current_tab($new_tab);
			$self->push_tab($new_tab);
		}
		
		# change content of the entry
		$content =~ s/\n/<br\/>/g;$content =~ s/\t/<tab\/>/g;
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
		die "Could not open file $selected\n";
	}
}

sub _fs_open_done {
	my ($self, $obj, $ev_info) = @_;
	
	my $fs_win = $obj->top_widget_get;
	$fs_win->del();
	
	return unless($ev_info);
	
	my $selected = Efl::ev_info2s($ev_info);
	
	$self->open_file($selected);
	
}

sub _close_tab_cb {
	my ($self) = @_;
	
	my $current_tab = $self->current_tab();
	
	if ($current_tab->changed() > 0) {
		my $popup = Efl::Elm::Popup->add($self->elm_mainwindow());
		
		$popup->part_text_set("default","Warning: Tab contains unsaved content. Close anyway?");
		
		my $btn1 = Efl::Elm::Button->add($popup);
		$btn1->text_set("Okay");
		$btn1->smart_callback_add("clicked" => sub {$current_tab->changed(0); $popup->del(); $self->_close_tab_cb});
		
		my $btn2 = Efl::Elm::Button->add($popup);
		$btn2->text_set("Cancel");
		$btn2->smart_callback_add("clicked" => sub {$popup->del});
		
		$popup->part_content_set("button1", $btn1);
		$popup->part_content_set("button2", $btn2);
		
		$popup->show();
	}
	else {
		
		my @tabs = @{$self->tabs}; 
		my $tab_id = $current_tab->id();
		$self->clear_tabs();
		splice @tabs,$tab_id,1;
		$self->refresh_tabs(@tabs);
	}
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

##################################
# tabsbar / tabs
##################################
sub clear_tabs {
	my ($self) = @_;
	
	foreach my $tab (@{$self->tabs}) {
		$tab->elm_toolbar_item->del();
		$tab->elm_toolbar_item(undef);
	}
	
	$self->tabs([]);
}

sub refresh_tabs {
	my ($self,@tabs) = @_;
	
	my $id = 0;
	foreach my $tab (@tabs) {
		$self->push_tab($tab);
		$tab->id($id);
		$id++;
	}
}

sub push_tab {
	my ($self, $tab) = @_;
	
	push @{$self->tabs}, $tab;
	my @tabs = @{$self->tabs};
	
	my $tabsbar = $self->elm_tabsbar();
	my $filename = $tab->filename() || "Untitled";
	
	my ($name,$dirs,$suffix) = fileparse($filename);
	$name = "$name*" if ($tab->changed()>0);
	 
	my $id = $#tabs;
	
	my $tab_item = $tabsbar->item_append(undef,$name, \&change_tab, [$self, $id]);
	
	$tab->elm_toolbar_item($tab_item);
	$tab_item->selected_set(1);
}


sub show_tab_menu {
	my ($menu, $evas, $obj, $evinfo) = @_;
	my $ev = Efl::ev_info2obj($evinfo, "Efl::Evas::Event::MouseDown");
	
	my $selected = $obj->selected_item_get();
	my $track = $selected->track();
	my ($x,$y,$w,$h) = $track->geometry_get();
	$selected->untrack();
	my $canvas = $ev->canvas();
	return unless ($canvas->{x} > $x && $canvas->{x} < $x+$w);
	
	if ($ev->button == 3) {
		$menu->move($canvas->{x},$canvas->{y});
		$menu->show();
	}
}

sub _no_change_tab {
	my ($data, $obj, $ev_info) = @_;
	my $tabitem = Efl::ev_info2obj($ev_info, "ElmToolbarItemPtr");
	$tabitem->selected_set(1);
} 
sub change_tab {
	my ($data, $obj, $ev_info) = @_;
	my $tabitem = Efl::ev_info2obj($ev_info, "ElmToolbarItemPtr");
	
	my $self = $data->[0];
	my $id = $data->[1];
	
	my $tabs = $self->tabs();
	my $entry = $self->entry;
	
	
		my $en=$entry->elm_entry;
		if ( ref($self->current_tab) eq "eSourceHighlight::Tab") {
			 my $current = $self->current_tab;
			 $current->content($en->entry_get);
			 $current->cursor_pos($en->cursor_pos_get());
		}
		else {
			warn "Warn: This is very curious :-S There is no current tab???\n";
		}
		my $tab = $tabs->[$id];
		$self->current_tab($tab);
		
		$entry->is_change_tab("yes");
		$en->entry_set($tab->content);
		$en->focus_set(1);
		
		$self->change_doctype_label();
		$self->change_doctype_options();
		
		######################
		# Clear search results
		######################
		$self->entry()->search()->clear_search_results();
		
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
	
	my $hbox = Efl::Elm::Box->add($vbox);
	$hbox->padding_set(25,25);
	$hbox->horizontal_set(1);
	$hbox->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$hbox->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$vbox->pack_end($hbox);
	$hbox->show();
	
	my $separator = Efl::Elm::Separator->add($hbox);
	$separator->horizontal_set(1);
	$separator->size_hint_weight_set(EVAS_HINT_EXPAND,0);
	$separator->size_hint_align_set(EVAS_HINT_FILL,EVAS_HINT_FILL);
	$hbox->pack_end($separator);
	$separator->show();
	
	my $doctype_label = Efl::Elm::Label->add($hbox);
	$doctype_label->text_set("Document Type: Unknown");
	$doctype_label->show(); 
	$hbox->pack_end($doctype_label);
	$self->elm_doctype_label($doctype_label);
	
	my $separator2 = Efl::Elm::Separator->add($hbox);
	$separator2->horizontal_set(1);
	$hbox->pack_end($separator2);
	$separator2->show();
	
	my $line_column_label = Efl::Elm::Label->add($hbox);
	$line_column_label->text_set("Line: 1 Column: 0");
	$line_column_label->show(); 
	$hbox->pack_end($line_column_label);
	$self->elm_linecolumn_label($line_column_label);
	
	my $separator3 = Efl::Elm::Separator->add($hbox);
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
		unless $AUTOLOAD =~m/tabs|entry|share_dir|current_tab|elm_mainwindow|elm_menu|elm_toolbar|elm_searchbar|elm_doctype_label|elm_src_highlight_check|elm_linewrap_check|elm_autoident_check|elm_linecolumn_label/;
	
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

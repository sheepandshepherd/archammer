/+
This file is part of Arc Hammer, a mod tool for Dark Forces.
Copyright (C) 2016  sheepandshepherd

Arc Hammer is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

Arc Hammer is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Arc Hammer; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
+/

module archammer.ui.tabgob;

import std.conv : to, text;
import std.string : toStringz, fromStringz;
import std.traits : EnumMembers;

debug import std.stdio : writeln;
import std.experimental.allocator.mallocator;

import archammer.ui.mainWindow;
import archammer.ui.util;
import archammer.ui.batch;
import archammer.util;
import archammer.arcgob;

import gtk.MessageDialog;
import gtk.Menu;
import gtk.MenuBar;
import gtk.MenuItem;
import gtk.Widget;
import gdk.Event;
import gtk.Label;
import gtk.Button;
import gtk.ProgressBar;
import gtk.Box;
import gtk.Grid;
import gtk.ComboBox, gtk.ComboBoxText;
import gtk.ToggleButton;
import gtk.CheckButton;
import gtk.RadioButton;
import gtk.Range;
import gtk.Scale;
import gtk.Paned;

import gtk.ScrolledWindow;
import gtk.Frame;
import gtk.Image;
import glib.Bytes;
import gdkpixbuf.Pixbuf;
import gtk.Entry;
import glib.ListG, glib.ListSG;

// Tree stuff for file tree
import gobject.Value;
import gtk.ListStore;
import gtk.TreeModelSort;
import gtk.TreeIter;
import gtk.TreePath;
import gtkc.gobjecttypes;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.CellEditableIF, gtk.CellRenderer, gtk.CellRendererText, gtk.CellRendererCombo, gtk.CellRendererToggle;

/++
Tab for extracting files from GOB archives

+/
class TabGob : Box, ArcTab
{
	ArcWindow window;
	
	Box tools; /// top toolbar
	Button openFile;
	Button extractFile;
	Button addFile;
	Button deleteFile;
	
	Box list; /// side list of all GOBs
	ListSG radioGroup; /// group for radio buttons in GOB list
	
	
	FileGob gob; /// currently selected GOB
	Box viewer; /// box showing the archive contents
	FileView fileView; /// TreeView

	this(ArcWindow window)
	{
		super(Orientation.VERTICAL, 4);
		
		this.window = window;
		
		tools = new Box(Orientation.HORIZONTAL, 0);
		openFile = new Button("Open",delegate void(Button b){
				if(gob is null) return;
				auto iter = fileView.getSelectedIter();
				if(iter is null) return;

				auto ptr = scoped!Value();
				iter.getValue(FileGob.TreeColumn.pointer,ptr);
				ArcGob.File f = cast(ArcGob.File)ptr.getPointer();
				debug writeln("Opened ",iter.getValueString(FileGob.TreeColumn.name),"/",f.name,
					" (size ",iter.getValueInt(FileGob.TreeColumn.size),"/",f.data.length,")");

				window.batch.openFile(f.name, f.data);
			});
		openFile.setTooltipText("Open the file directly in ArcHammer");
		extractFile = new Button("Extract...",delegate void(Button b){
				import std.path, std.file;
				import std.string : toUpper;
				import gtk.FileChooserDialog, gtk.FileChooserIF;
				import std.typecons : scoped;

				if(gob is null) return;
				auto iter = fileView.getSelectedIter();
				if(iter is null) return;
				
				auto ptr = scoped!Value();
				iter.getValue(FileGob.TreeColumn.pointer,ptr);
				ArcGob.File f = cast(ArcGob.File)ptr.getPointer();

				FileChooserDialog fileChooser = new FileChooserDialog("Extract File", window, FileChooserAction.SAVE);
				scope(exit) fileChooser.destroy();

				/// Filters???
				fileChooser.addFilter(FileFilters.all);
				
				fileChooser.setModal(true);
				fileChooser.setLocalOnly(true);
				fileChooser.setCurrentName(f.name);
				
				auto response = fileChooser.run();
				if(response == ResponseType.OK)
				{
					import std.file;
					/// save to absolute path selected in window
					auto path = fileChooser.getFilename();
					
					fileChooser.hide();
					
					write(path, f.data);
				}
			});
		addFile = new Button("Add...",delegate void(Button b){

			});
		deleteFile = new Button("Delete",delegate void(Button b){

			});

		// not ready yet
		addFile.setSensitive(false);
		deleteFile.setSensitive(false);

		tools.packStart(new Label(""),true,true,0); // temp blank to scoot the rest to the right side
		foreach(b; [openFile, extractFile, addFile, deleteFile]) tools.packStart(b,false,false,2);

		packStart(tools, false, false, 0);
		
		
		list = new Box(Orientation.VERTICAL, 2);
		auto listScroll = new ScrolledWindow(list);
		listScroll.setPolicy(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
		auto listFrame = new Frame(listScroll, "GOB Archives");
		listFrame.setShadowType(ShadowType.NONE);
		
		viewer = new Box(Orientation.VERTICAL, 0);
		auto fileScroll = new ScrolledWindow(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		fileScroll.setHexpand(true);
		fileScroll.setVexpand(true);
		fileScroll.setOverlayScrolling(false);
		fileView = new FileView(null); // set the model to null; it should be obtained from the selected GOB
		fileScroll.add(fileView);
		viewer.add(fileScroll);

		auto pane = new Paned(Orientation.HORIZONTAL);
		pane.add1(listFrame);
		pane.add2(viewer);
		pane.setPosition(180);
		
		packStart(pane, true, true, 0);
	}
	
	/// List item for GOBs. Actual data and FileGob gotten from FileEntry in Batch tab.
	class MiniEntry : Box, Batch.FileEntry.SubEntry
	{
		Batch.FileEntry fe;
		RadioButton button;
		
		this(Batch.FileEntry fe)
		{
			super(Orientation.HORIZONTAL, 4);
			this.fe = fe;
			
			button = new RadioButton(fe.name.getText());
			packStart(button, true, true, 4);
			button.addOnClicked(delegate void(Button b)
				{
					gob = cast(FileGob)fe.file;
					updateGobViewer();
				});
		}
		~this()
		{
			if(gob is cast(FileGob)fe.file)
			{
				debug writeln("Unselecting self from TabGob");
				gob = null;
				updateGobViewer();
			}

			hide();
			destroy();
		}
	}

	MiniEntry addEntry(Batch.FileEntry fe)
	{
		auto me = new MiniEntry(fe);
		list.add(me);
		return me;
	}
	
	MiniEntry[] getMiniEntries()
	{
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration : map;
		import std.range : array;
		
		ListG childList = list.getChildren();
		if(childList is null) return null;
		scope(exit) childList.free();
		return childList.toArray!Box().map!( f=>cast(MiniEntry)f )().array;
	}
	
	/++
	Called when switching to this tab.
	+/
	void updateTab()
	{
		list.showAll();
	}

	/++
	Updates the list of files in the selected GOB
	
	+/
	void updateGobViewer()
	{
		// TODO: reset file list, remake if gob is different
		if(gob is null)
		{
			fileView.setModel(null);
			return;
		}



		fileView.setModel(gob.fileListStore);
	}






	/++
	List of files in selected GOB.

	+/
	static class FileView : TreeView
	{
		private TreeViewColumn nameColumn, sizeColumn;
		this(ListStore fileListStore)
		{
			setActivateOnSingleClick(true);

			nameColumn = new TreeViewColumn("Filename", new CellRendererText(), "text", FileGob.TreeColumn.name);
			appendColumn(nameColumn);

			/// TODO: Need a CellDataFunction for the Size column to display commas.
			auto sizeRenderer = new CellRendererText();
			sizeRenderer.setProperty("family", "Monospace");
			sizeRenderer.setProperty("xalign",new Value(1f));
			sizeColumn = new TreeViewColumn("Size (bytes)", sizeRenderer, "text", FileGob.TreeColumn.size);
			appendColumn(sizeColumn);
			
			setModel(fileListStore);
			
			addOnRowActivated(delegate void(TreePath path,TreeViewColumn column,TreeView treeView)
				{
					TreeIter iter = new TreeIter();
					auto get = getModel().getIter(iter, path);
					if(!get) throw new Exception("TreeIter from activated row could not be gotten from the TreePath passed to OnRowActivated delegate.");
					auto ptr = scoped!Value();
					iter.getValue(FileGob.TreeColumn.pointer,ptr);
					ArcGob.File f = cast(ArcGob.File)ptr.getPointer();
					debug writeln("Activated ",iter.getValueString(FileGob.TreeColumn.name),"/",f.name,
						" (size ",iter.getValueInt(FileGob.TreeColumn.size),"/",f.data.length,")");
					
				});
		}
	}

}












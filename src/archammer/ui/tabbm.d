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

module archammer.ui.tabbm;

import std.conv : to, text;
import std.string : toStringz, fromStringz;
import std.traits : EnumMembers;

debug import std.stdio : writeln;

import archammer.ui.mainWindow;
import archammer.ui.util;
import archammer.ui.batch;
import archammer.util;
import archammer.arcpal;
import archammer.arcbm;

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
import gtk.CheckButton;
import gtk.RadioButton;
import gtk.Paned;

import gtk.ScrolledWindow;
import gtk.Frame;
import gtk.Image;
import glib.Bytes;
import gdkpixbuf.Pixbuf;
import gtk.Entry;
import glib.ListG, glib.ListSG;

/++
Tab for viewing and editing BMs.

+/
class TabBm : Box, ArcFileList
{
	ArcWindow window;
	Batch batch;
	
	Box tools; /// top toolbar for editing the BM
	Box list; /// side list of all BMs
	ListSG radioGroup; /// group for radio buttons in BM list
	Box viewer; /// box showing the texture
	
	Image image;
	
	this(ArcWindow window)
	{
		super(Orientation.VERTICAL, 4);
		
		this.window = window;
		this.batch = window.batch;
		
		tools = new Box(Orientation.HORIZONTAL, 0);
		packStart(tools, false, false, 0);
		
		list = new Box(Orientation.VERTICAL, 2);
		auto listScroll = new ScrolledWindow(list);
		listScroll.setPolicy(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
		auto listFrame = new Frame(listScroll, "Textures");
		listFrame.setShadowType(ShadowType.NONE);
		
		viewer = new Box(Orientation.VERTICAL, 0);
		image = new Image();
		viewer.add(image);
		
		auto pane = new Paned(Orientation.HORIZONTAL);
		pane.add1(listFrame);
		pane.add2(viewer);
		pane.setPosition(220);
		
		packStart(pane, true, true, 0);
	}
	
	/// List item for BM files. Actual data and FileBM gotten from FileEntry in Batch tab.
	class MiniEntry : Box
	{
		Batch.FileEntry fe;
		Image thumbnail;
		RadioButton button;
		
		this(Batch.FileEntry fe)
		{
			super(Orientation.HORIZONTAL, 4);
			this.fe = fe;
			thumbnail = new Image(fe.file.thumbnail);
			packStart(thumbnail, false, false, 0);
			
			button = new RadioButton(fe.file.path?fe.file.baseName:"new");
			packStart(button, true, true, 4);
			button.addOnClicked(delegate void(Button b)
			{
				updateViewer(cast(FileBm)fe.file);
			});
		}
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
	Get the list of BM files from Batch and create their mini-entries
	+/
	void updateList()
	{
		import std.range;
		foreach(entry; getMiniEntries().retro)
		{
			entry.hide();
			entry.destroy();
			object.destroy(entry);
		}
		foreach(entry; batch.getEntries())
		{
			if(cast(FileBm)entry.file)
			{
				debug writeln("Adding BM ",entry.file.path);
				list.add(new MiniEntry(entry));
			}
		}
		list.showAll();
	}
	
	/++
	Show a BM in the viewer
	+/
	void updateViewer(FileBm bm)
	{
		image.setFromPixbuf(bm.tex);
	}
}












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
import std.experimental.allocator.mallocator;

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

/++
Tab for viewing and editing BMs.

+/
class TabBm : Box, ArcFileList
{
	ArcWindow window;
	Batch batch;
	
	Box tools; /// top toolbar for editing the BM
	
	/// currently selected PAL
	@property FilePal pal()
	{
		import std.algorithm.searching, std.algorithm.iteration, std.range;
		int id = paletteBox.getActive();
		if(id <= 0) return null; // default selected
		id -= 1; // ignore the default option
		auto entries = batch.getEntries();
		auto palettes = entries.filter!( e => (cast(FilePal) e.file !is null));
		// assume palettes is long enough, since the combobox list was generated from the same list:
		auto palArr = palettes.array;
		debug writeln("id = ", id, "; palArr.length = ", palArr.length);
		return cast(FilePal) palArr[cast(size_t)id].file;
	}
	ComboBoxText paletteBox; /// combobox for palette
	CheckButton paletteView; /// whether the viewer should palettize the texture for display
	Scale zoom;
	
	
	Box list; /// side list of all BMs
	ListSG radioGroup; /// group for radio buttons in BM list
	
	
	FileBm bm; /// currently selected BM
	Box viewer; /// box showing the texture
	Bytes texData; /// data for tex Pixbuf
	Pixbuf tex; /// the texture buffer (including zoom)
	Image image;
	
	this(ArcWindow window)
	{
		super(Orientation.VERTICAL, 4);
		
		this.window = window;
		this.batch = window.batch;
		
		tools = new Box(Orientation.HORIZONTAL, 0);
		
		paletteBox = new ComboBoxText(false);
		paletteBox.addOnChanged((ComboBoxText c){ updateViewer(); });
		tools.packStart(new Label("Palette:"), false, false, 2);
		tools.packStart(paletteBox, false, false, 2);
		
		paletteView = new CheckButton("View palettized");
		paletteView.setActive(true);
		paletteView.addOnToggled((ToggleButton t){ updateViewer(); });
		tools.packStart(paletteView, false, false, 2);
		
		auto palToColors = new Button("PAL->Colors");
		palToColors.setTooltipText("WIP\nSet the texture's internal colors to match the selected palette");
		palToColors.addOnClicked((Button b){  });
		auto colorsToPal = new Button("Colors->Indices");
		colorsToPal.setTooltipText("WIP\nConvert the texture to the selected palette by matching its current internal colors as closely as possible");
		colorsToPal.addOnClicked((Button b){  });
		tools.packStart(palToColors, false, false, 2);
		tools.packStart(colorsToPal, false, false, 2);
		
		zoom = new Scale(Orientation.HORIZONTAL, 1.0, 8.0, 1.0);
		zoom.setDigits(0);
		zoom.setValuePos(PositionType.RIGHT);
		zoom.setValue(1.0);
		zoom.addOnValueChanged((Range r){ updateViewer(); });
		tools.packStart(new Label("Zoom:"), false, false, 2);
		tools.packStart(zoom, true, true, 2);
		
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
			
			button = new RadioButton(fe.name.getText());
			packStart(button, true, true, 4);
			button.addOnClicked(delegate void(Button b)
			{
				bm = cast(FileBm)fe.file;
				updateViewer();
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
		
		FileBm newBm = null;
		FilePal currentPal = pal;
		
		// clear the BM list
		foreach(entry; getMiniEntries().retro)
		{
			entry.hide();
			entry.destroy();
			object.destroy(entry);
		}
		// clear the palette combobox
		paletteBox.removeAll();
		paletteBox.appendText("<default>");
		paletteBox.setActive(0);
		
		foreach(entry; batch.getEntries())
		{
			auto entryBm = cast(FileBm)entry.file;
			auto entryPal = cast(FilePal)entry.file;
			
			if(entryBm)
			{
				debug writeln("Adding BM ",entry.file.path);
				list.add(new MiniEntry(entry));
				if(entryBm is bm) newBm = entryBm;
			}
			else if(entryPal)
			{
				paletteBox.appendText(entry.file.name);
				if(entryPal is currentPal)
				{
					paletteBox.setActive(paletteBox.getModel().iterNChildren(null) - 1); // select it
				}
			}
		}
		
		bm = newBm;
		
		list.showAll();
		
		updateViewer();
	}
	
	/++
	Refresh the BM shown in the viewer.
	Should be called whenever zooming or changing palette.
	+/
	void updateViewer()
	{
		// delete old texture
		if(tex)
		{
			object.destroy(tex);
			tex = null; // nullify, since it's not guaranteed to be replaced if current bm is null
		}
		if(texData)
		{
			object.destroy(texData);
			texData = null;
		}
		
		if(bm is null) return; // empty selection, do nothing
		
		ArcBm fileBm = bm.fileBm;
		
		size_t size = fileBm.w*fileBm.h*4;
		ubyte[] _data = cast(ubyte[]) Mallocator.instance.allocate(size);
		scope(exit) Mallocator.instance.deallocate(_data); // data is copied by Bytes ctor, so free this buffer afterwards
		
		ArcPal viewPal = null;
		if(paletteView.getActive())
		{
			auto _pal = pal;
			if(_pal !is null)
			{
				viewPal = pal.filePal;
			}
		}
		fileBm.copyRGBA(_data, false, viewPal);
		
		texData = new Bytes(_data);
		tex = new Pixbuf(texData, Colorspace.RGB, true, 8, cast(int)fileBm.w, cast(int)fileBm.h, cast(int)fileBm.w*4);
		
		// scale texture
		int scale = cast(int) zoom.getValue();
		if(scale > 1)
		{
			tex = tex.scaleSimple(scale * tex.getWidth(), scale * tex.getHeight(), InterpType.HYPER);
		}
		image.setFromPixbuf(tex);
	}
}












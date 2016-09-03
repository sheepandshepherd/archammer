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

module archammer.ui.settings;


import std.conv : to, text;
import std.string : toStringz, fromStringz;
import std.traits : EnumMembers;
import std.meta : AliasSeq;
import std.algorithm.iteration;

debug import std.stdio : writeln;
import std.experimental.allocator, std.experimental.allocator.mallocator;

import archammer.ui.mainWindow;
import archammer.ui.util;
import archammer.ui.batch;
import archammer.util;
import archammer.arcgob;

import yaml;
alias YamlNode = dyaml.node.Node;

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

import gtk.DragAndDrop, gtk.TargetList, gtk.TargetEntry, gdk.DragContext, gtk.SelectionData;

class Settings : Box, ArcTab
{
	ArcWindow window;

	Entry dosBoxExeEntry, darkCDEntry, darkExeEntry;
	CheckButton fullscreenCheck;

	this(ArcWindow window)
	{
		this.window = window;
		super(Orientation.VERTICAL, 4);


		// Dark Forces settings ****************************************************************************************
		auto dfBox = new Grid();
		auto dfFrame = new Frame(dfBox,"Dark Forces");
		packStart(dfFrame,true,true,4);

		dfBox.attach(new Label("DosBox path: "),0,0,1,1);
		string dosboxDefault;
		version(Win32) dosboxDefault = `C:\Program Files\DOSBox\DOSBox.exe`;
		else version(Win64) dosboxDefault = `C:\Program Files (x86)\DOSBox\DOSBox.exe`;
		else dosboxDefault = "dosbox";
		dosBoxExeEntry = new Entry(dosboxDefault,255);
		dosBoxExeEntry.setHexpand(true);
		dosBoxExeEntry.setTooltipText("Path to DosBox executable");
		dfBox.attach(dosBoxExeEntry, 1,0,2,1);
		
		dfBox.attach(new Label("DF CD path: "),0,1,1,1);
		darkCDEntry = new Entry("",255);
		darkCDEntry.setHexpand(true);
		dfBox.attach(darkCDEntry,1,1,2,1);
		dfBox.attach(new Label("Dark.exe path: "),0,2,1,1);
		darkExeEntry = new Entry("",255);
		darkExeEntry.setHexpand(true);
		darkExeEntry.setTooltipText("Path to Dark Forces executable");
		dfBox.attach(darkExeEntry,1,2,2,1);
		
		fullscreenCheck = new CheckButton("Fullscreen");
		dfBox.attach(fullscreenCheck,0,3,3,1);
		// *************************************************************************************************************



	}

	public void load(in char[] source)
	{
		char[] str = Mallocator.instance.makeArray!char(source.length);
		scope(exit) Mallocator.instance.deallocate(cast(void[])str);
		str[] = source[];
		auto loader = Loader.fromString(str);
		auto root = loader.load();
		load(root);
	}
	public ubyte[] save()
	{
		auto n = getYamlData();

		import dyaml.stream;
		auto stream = new YMemoryStream();
		
		auto dumper = Dumper(stream);
		dumper.explicitStart = false;
		dumper.resolver = new Resolver();
		auto rep = new Representer();
		rep.defaultScalarStyle = ScalarStyle.Plain;
		rep.defaultCollectionStyle = CollectionStyle.Block;
		dumper.representer = rep;
		dumper.dump(n);

		return stream.data;
	}

	private void load(YamlNode n)
	{
		if(n.containsKey("dosboxPath")) dosBoxExeEntry.setText(n["dosboxPath"].as!string);
		if(n.containsKey("dfPath")) darkExeEntry.setText(n["dfPath"].as!string);
		if(n.containsKey("cdPath")) darkCDEntry.setText(n["cdPath"].as!string);
		if(n.containsKey("fullscreen")) fullscreenCheck.setActive(n["fullscreen"].as!bool);
	}
	private YamlNode getYamlData()
	{
		YamlNode[string] nodes;
		nodes["dosboxPath"] = YamlNode(dosBoxExeEntry.getText());
		nodes["dfPath"] = YamlNode(darkExeEntry.getText());
		nodes["cdPath"] = YamlNode(darkCDEntry.getText());
		nodes["fullscreen"] = YamlNode(fullscreenCheck.getActive());

		YamlNode root = YamlNode(nodes);

		return root;
	}

	override void updateTab()
	{

	}
}


﻿/+
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

module archammer.ui.batch;

import std.conv : to, text;
import std.string : toStringz, fromStringz;
import std.traits : EnumMembers;

debug import std.stdio;
import std.experimental.allocator.mallocator;

import archammer.ui.util;
import archammer.util;
import archammer.arc3do;
import archammer.arcpal;
import archammer.arcbm;
import archammer.arcgob;

import derelict.assimp3.assimp;

import archammer.ui.mainWindow;
import gtk.MainWindow;
import gtk.Dialog, gtk.FileChooserDialog, gtk.FileChooserIF;
import gtk.MessageDialog;
import gtk.TextView;
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

import gtk.ScrolledWindow;
import gtk.Frame;
import gtk.Image;
import glib.Bytes;
import gdkpixbuf.Pixbuf;
import gtk.Entry;

import glib.ListG, glib.ListSG;
import gio.FileIF;
import gtk.FileFilter;
import gobject.Value;
import gtk.ListStore;
import gtk.TreeModelSort;
import gtk.TreeIter;
import gtkc.gobjecttypes;
import gtk.TreeView;
import gtk.TreeViewColumn;
import gtk.CellEditableIF, gtk.CellRenderer, gtk.CellRendererText, gtk.CellRendererCombo, gtk.CellRendererToggle;

class Batch : Box
{
	ArcWindow window;
	
	enum OutputDirectory : int
	{
		sameDir,  /// save each output file in the same folder as its input
		arcHammerDir  /// save all output files in the Arc Hammer folder
	}
	
	Box fileBox;
	CheckButton headerLoadDependencies;
	ComboBoxText headerOutputDirectory;
	
	this(ArcWindow window)
	{
		super(Orientation.VERTICAL, 4);
		
		this.window = window;
		
		auto header = new Box(Orientation.HORIZONTAL, 4);
		packStart(header,false,false,4);
		header.setHomogeneous(true);
		auto headerIn = new Box(Orientation.VERTICAL, 4);
		auto headerOut = new Box(Orientation.VERTICAL, 4);
		header.packStart(headerIn,true,true,2);
		header.packStart(headerOut,true,true,2);
		headerIn.add(new Label("Input"));
		auto headerLoad = new Button("Open...");
		headerIn.add(headerLoad);
		headerLoad.addOnClicked(&loadFileEvent);
		headerLoadDependencies = new CheckButton("Auto-load dependencies");
		version(none) headerIn.add(headerLoadDependencies); /// TODO
		headerLoadDependencies.setTooltipText("Automatically add any other files referenced in loaded files");
		
		headerOut.add(new Label("Output"));
		auto headerSave = new Button("Save all");
		headerOut.add(headerSave);
		headerSave.setTooltipText("Save all open files that have a save format set");
		headerSave.addOnClicked(delegate void(Button button)
			{
				auto fileEntries = getEntries();
				foreach(fe; fileEntries)
				{
					fe.convert();
				}
			});
		auto headerOutHBox = new Box(Orientation.HORIZONTAL, 4);
		headerOut.add(headerOutHBox);
		headerOutHBox.packStart(new Label("Output directory:"),false,false,2);
		headerOutputDirectory = new ComboBoxText(false);
		headerOutHBox.packStart(headerOutputDirectory,true,true,2);
		headerOutputDirectory.appendText("Same as inputs");
		headerOutputDirectory.appendText("Arc Hammer directory");
		headerOutputDirectory.setActive(1);
		
		fileBox = new Box(Orientation.VERTICAL, 2);
		auto fileScroll = new ScrolledWindow(fileBox);
		fileScroll.setPolicy(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
		auto fileFrame = new Frame(fileScroll, null);
		
		/////////////////////////////////
		
		packStart(fileFrame,true,true,0);
	}
	
	void showErrorDialog(string title, string header, string message)
	{
		import std.algorithm.searching : count;
		import std.algorithm.comparison : min;
		
		Dialog m = new Dialog(title, window, DialogFlags.DESTROY_WITH_PARENT, ["Ok"], [ResponseType.CLOSE]);
		m.setDefaultSize(400, 200 + 20 * min( 10, message.count('\n') ));
		
		auto box = m.getContentArea();
		box.packStart(new Label(header),false, false, 8);
		auto scroll = new ScrolledWindow(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		auto l = new TextView();//Label(e.msg);
		l.setEditable(false);
		l.appendText(message, false);
		
		///l.setLineWrap(true);
		l.setHexpand(true);
		l.setVexpand(true);
		l.setHalign(Align.START);
		l.setValign(Align.START);
		scroll.setOverlayScrolling(false);
		
		scroll.add(l);
		box.packStart(scroll,true,true,8);
		
		box.showAll();
		
		m.run();
		m.destroy();
	}
	
	void loadFileEvent(Button button)
	{
		showLoadFileDialog();
	}
	
	/// shows a FileChooserDialog that will process and load any chosen files.
	/// unsuccessful loads will be aborted with an error message and not added to the FileEntry list.
	void showLoadFileDialog()
	{
		import std.typecons : scoped;
		auto fileChooser = new FileChooserDialog("Open File", window, FileChooserAction.OPEN);
		scope(exit) fileChooser.destroy();
		fileChooser.setSelectMultiple(true);
		/// add all the filters of loadable files:
		foreach(ref ff; [AllFileFilters])
		{
			fileChooser.addFilter(ff);
		}
		
		fileChooser.setModal(true);
		fileChooser.setLocalOnly(true);
		
		auto response = fileChooser.run();
		if(response == ResponseType.OK)
		{
			import std.algorithm.iteration;
			import std.range : array;
			import glib.ListSG;
			/// load each
			auto list = fileChooser.getFiles();
			scope(exit) list.free(); /// ObjectGs get `unref`ed by the D destructor.
			FileIF[] files = (cast(FileIF*)list.data)[0..list.length];
			
			string[] paths = files.map!(f=>f.getPath()).array;
			
			fileChooser.hide();
			
			foreach(f; paths)
			{
				import std.file;
				if(f.exists)
				{
					ubyte[] data = cast(ubyte[])read(f);
					openFile(f, data);
				}
			}
			
			
			files.each!(f=>(object.destroy(f)));
		}
	}
	
	/// Open a file from a path, determine its type, and add it to a FileEntry in the Batch UI if successful.
	/// Params:
	/// 	filePath = the path used to naively determine type and default save location.
	/// 		For GOB-extracted files, this includes the GOB path ~ the filename.
	/// 	fileData = the actual data to load, either from the file or from GOB
	/// 
	/// Returns: the newly created FileEntry, or null if the file wasn't loadable
	FileEntry openFile(string filePath, in ubyte[] fileData)
	{
		import std.path, std.file;
		import std.uni : icmp;
		try
		{
			auto ext = extension(filePath);
			FileEntry fe;
			if(  FileFilters.arc3do.matchFile(filePath)  )
			{
				auto arc3do = Arc3do.load3doText(cast(string)fileData);
				fe = addFile(new File3do(filePath, arc3do));
				fe.outputType.setActive(2); // default to OBJ export
			}
			else if( FileFilters.assimp.matchFile(filePath) )
			{
				auto arc3do = Arc3do.loadMeshData(fileData, ext);
				fe = addFile(new File3do(filePath, arc3do));
				fe.outputType.setActive(1); // default to 3DO export
			}
			else if( FileFilters.arcPal.matchFile(filePath) )
			{
				auto arcPal = ArcPal.loadData(fileData);
				fe = addFile(new FilePal(filePath, arcPal));
				fe.outputType.setActive(2);
			}
			else if( FileFilters.arcBm.matchFile(filePath) )
			{
				auto arcBm = ArcBm.loadData(fileData);
				fe = addFile(new FileBm(filePath, arcBm));
				fe.outputType.setActive(2);
			}
			else if( FileFilters.arcGob.matchFile(filePath) )
			{
				auto arcGob = ArcGob.loadData(fileData);
				fe = addFile(new FileGob(filePath, arcGob));
			}
			return fe; // will be null if nothing opened
		}
		catch(Exception e)
		{
			showErrorDialog("Load exception", "Error loading file <"~filePath~">:", e.msg);
		}
		return null;
	}
	
	/// Add an open file to the Batch UI
	FileEntry addFile(File f)
	{
		auto fe = new FileEntry(f);
		addFileEntry(fe);
		return fe;
	}
	
	void addFileEntry(FileEntry fe)
	{
		fileBox.add(fe);
		fe.showAll();
	}
	
	FileEntry getNamedEntry(string name)
	{
		import std.uni : icmp;
		import std.algorithm.searching : countUntil;
		
		ListG childList = fileBox.getChildren();
		scope(exit) childList.free();
		Frame[] children = childList.toArray!Frame();
		if(children.length == 0) return null; // no children
		
		ptrdiff_t index = children.countUntil!(  (Frame f, string n)=>(icmp( (cast(FileEntry)f).name.getText(),n )==0)  )(name);
		if(index == -1) return null; // name not present
		
		return cast(FileEntry)children[index]; // first occurrence of name (ignore duplicates)
	}
	
	FileEntry[] getEntries()
	{
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration : map;
		import std.range : array;
		
		ListG childList = fileBox.getChildren();
		if(childList is null) return null;
		scope(exit) childList.free();
		return childList.toArray!Frame().map!( f=>cast(FileEntry)f )().array;
	}
	
	class FileEntry : Frame
	{
		/// Small version of the FileEntry in the tab for this file type
		interface SubEntry
		{
			void select(Button b);
		}
		SubEntry subEntry;
		File file;
		uint outputFormat = 0;
		
		Image thumbnail;
		Entry name;
		
		ComboBoxText outputType;
		Button convertButton;

		void jumpToSubEntry(Button button)
		{
			if(cast(FileGob)file) window.tabs.setCurrentPage(window.tabGob);
			else if(cast(FileBm)file) window.tabs.setCurrentPage(window.tabBm);
			
			if(subEntry !is null) subEntry.select(null);
		}
		
		this(File file)
		{
			import gdk.RGBA;
			
			this.file = file;
			auto box = new Box(Orientation.HORIZONTAL, 2);
			box.setHomogeneous(true);
			super(box, file.type);
			box.setBorderWidth(2);
			auto inBox = new Box(Orientation.HORIZONTAL, 0);
			box.add(inBox);
			
			thumbnail = new Image();
			
			string nameText = file.name;
			name = new Entry(nameText,8);
			auto viewButton = new Button("View");
			bool viewable = cast(FileGob)file || cast(FileBm)file;
			viewButton.setSensitive(viewable);
			if(viewable)
			{
				viewButton.addOnClicked(&this.jumpToSubEntry);
			}
			auto closeButton = new Button("x");
			closeButton.setName("closeFile"); // red background
			closeButton.addOnClicked(delegate void(Button button)
			{
				hide();
				destroy();
				object.destroy(this);
			});
			
			inBox.packStart(thumbnail, false, false, 2);
			inBox.packStart(name, true, true, 4);
			inBox.packStart(viewButton, false, false, 2);
			inBox.packStart(closeButton, false, false, 2);
			
			
			auto outBox = new Box(Orientation.HORIZONTAL, 0);
			box.add(outBox);
			outputType = new ComboBoxText(false);
			outputType.appendText("");
			foreach(sf; file.file.saveFormats)
			{
				outputType.appendText(sf.name);
			}
			
			convertButton = new Button("Save");
			convertButton.setName("saveFile"); // green background
			convertButton.addOnClicked( (b)=>convert() );
			
			outputType.setTitle("Format");
			outputType.setTooltipText("File format to save in (or blank to leave this file unmodified)");
			outputType.addOnChanged(delegate void(ComboBoxText c)
				{
					convertButton.setSensitive(c.getActive() != 0);
				});
			outputType.setActive(0);
			
			outBox.packStart(outputType, true, true, 2);
			outBox.packStart(convertButton, false, false, 2);
			
			refresh();
			
			/// create subentry
			if(cast(FileBm)file)
			{
				subEntry = window.tabBm.addEntry(this);
			}
			if(cast(FileGob)file)
			{
				subEntry = window.tabGob.addEntry(this);
			}
		}
		
		~this()
		{
			if(subEntry !is null) object.destroy(subEntry);
		}
		
		/// save this entry's file using the settings specified in the UI
		void convert()
		{
			string nameText = name.getText();
			if(nameText is null || nameText.length == 0) return; /// TODO: error message
			file.save(nameText, outputType.getActive(), headerOutputDirectory.getActive()==0);
		}
		
		/// update the GTK-D widgets
		void refresh()
		{
			if(file.thumbnail is null)
			{
				import std.file : exists;
				bool fileExists = file.path !is null && exists(file.path);
				thumbnail.setFromIconName(fileExists?"document-open":"document-new", IconSize.DND);
			}
			else
			{
				thumbnail.setFromPixbuf(file.thumbnail);
			}
		}
	}
	
	
	
	
	
	
}




/// File data for batch window
abstract class File
{
	immutable string path; // input path, or null if it's a new file
	abstract pure @property string type(); /// the file type (not format)
	
	/++
	32x32 Pixbuf to be used in the UI thumbnail, or null to use a default icon.
	+/
	Pixbuf thumbnail = null;
	
	@property string baseName()
	{
		import std.path;
		if(path is null) return null;
		return stripExtension(std.path.baseName(path));
	}
	
	/++
	The text to display in lists containing this file
	+/
	@property string name()
	{
		return path?baseName:"new";
	}
	
	@disable this(); /// no default constructor because we need to set immutable `path`
	this(string path)
	{
		this.path = path;
	}
	
	Savable file;
	
	/// Save the file.
	/// params:
	/// 	name = the filename without directories or extension to use for saving
	/// 	format = the id of the file format to save in (from the formats specified in outputTypes)
	/// 	local = whether to save in the same directory as the input. Otherwise, file is saved in Arc Hammer output directory.
	final void save(string name, int format, bool local = true)
	{
		import std.path, std.file;
		import std.string : toUpper;
		
		if(format == 0) return; // no format set
		format -= 1; // ignore the "blank" option that's index 0 in the UI; `format` should match the file class's saveFormats array
		assert(format < file.saveFormats.length);
		auto saveFormat = file.saveFormats[format];
		
		string savePath;
		if(local && path !is null)
		{
			savePath = buildPath(path.dirName, name.toUpper);
		}
		else
		{
			savePath = buildPath(thisExePath.dirName, name.toUpper);
		}
		
		savePath = savePath.setExtension(saveFormat.extension);
		if(exists(savePath)) remove(savePath);
		write(savePath, saveFormat.dataFunction());
	}
}

class FileGob : File
{
	override pure @property string type() { return "GOB Archive"; }
	
	@property ArcGob fileGob() { return cast(ArcGob)file; }

	ListStore fileListStore;
	/// $(D fileListStore) column numbers
	static enum TreeColumn : int
	{
		name,
		pointer,
		size,

	}
	private static GType[] TreeTypes = [GType.STRING, GType.POINTER, GType.INT,];

	/// regenerate the $(D fileListStore) from the GOB's internal file list
	void refreshFileListStore()
	{
		// clear old list
		fileListStore.clear();
		foreach(f; fileGob.files[])
		{
			auto iter = fileListStore.createIter();
			fileListStore.setValue(iter, TreeColumn.name, f.name);
			Value ptr = new Value();
			ptr.init(GType.POINTER);
			ptr.setPointer(cast(void*)(f));
			fileListStore.setValue(iter, TreeColumn.pointer, ptr);
			fileListStore.setValue(iter, TreeColumn.size, cast(int)f.data.length);
		}
	}
	
	this(string path, ArcGob file)
	{
		super(path);
		this.file = file;


		fileListStore = new ListStore(TreeTypes);
		refreshFileListStore();
	}
}

class File3do : File
{
	override pure @property string type() { return "Mesh"; }
	
	@property Arc3do file3do() { return cast(Arc3do)file; }
	
	this(string path, Arc3do file)
	{
		super(path);
		this.file = file;
		
		// TODO: generate OpenGL stuff
	}
	
	/// TODO: OpenGL handles for this object. Generate at load so we can display in the View3do tab
}

class FilePal : File
{
	override pure @property string type() { return "Palette"; }
	
	@property ArcPal filePal() { return cast(ArcPal)file; }
	
	Bytes data;
	
	this(string path, ArcPal file)
	{
		import std.range;
		import core.stdc.stdlib : malloc, free;
		super(path);
		this.file = file;
		auto palBm = ArcBm.paletteBm(file);
		
		ubyte[] _data = (cast(ubyte*)malloc(256*4))[0..256*4];
		scope(exit) free(_data.ptr);
		
		palBm.copyRGBA(_data, false);
		
		data = new Bytes(_data);
		
		// 16x16 version, to be resized because there doesn't seem to be a way to stretch Images
		auto t16 = new Pixbuf(data, Colorspace.RGB, true, 8, 16, 16, 16*4);
		
		thumbnail = t16.scaleSimple(32, 32, InterpType.NEAREST);
		
		object.destroy(t16);
	}
}

class FileBm : File
{
	override pure @property string type() { return "Texture"; }
	
	@property ArcBm fileBm() { return cast(ArcBm)file; }
	
	Bytes data;
	Pixbuf tex;
	
	void refreshTex()
	{
		if(tex) object.destroy(tex);
		if(data) object.destroy(data);
		
		size_t size = fileBm.w*fileBm.h*4;
		ubyte[] _data = cast(ubyte[]) Mallocator.instance.allocate(size);
		scope(exit) Mallocator.instance.deallocate(_data); // data is copied by Bytes ctor, so free this buffer afterwards
		
		fileBm.copyRGBA(_data, false);
		
		data = new Bytes(_data);
		tex = new Pixbuf(data, Colorspace.RGB, true, 8, cast(int)fileBm.w, cast(int)fileBm.h, cast(int)fileBm.w*4);
	}
	
	this(string path, ArcBm file)
	{
		import std.range;
		super(path);
		this.file = file;
		
		refreshTex();
		
		// make 32x32 thumbnail
		if(fileBm.w == fileBm.h)
		{
			thumbnail = tex.scaleSimple(32, 32, InterpType.BILINEAR);
		}
		else
		{
			import std.algorithm.comparison;
			size_t scaleFactor = max(fileBm.w, fileBm.h) / 32;
			int sx = cast(int) (fileBm.w/scaleFactor),  sy = cast(int) (fileBm.h/scaleFactor);
			sx = clamp(sx, 2, 32);
			sy = clamp(sy, 2, 32);
			Pixbuf temp = tex.scaleSimple(sx, sy, InterpType.BILINEAR);
			int ox = (32-sx)/2, oy = (32-sy)/2;
			thumbnail = new Pixbuf(Colorspace.RGB, true, 8, 32, 32);
			thumbnail.fill(0); // transparency
			temp.copyArea(0, 0, sx, sy, thumbnail, ox, oy);
			object.destroy(temp);
		}
	}
}


/// Create a GTK+ ListStore from an array of strings
ListStore createStringListStore(in string[] strings)
{
	auto ret = new ListStore([GType.STRING]);
	foreach(s; strings)
	{
		auto iter = ret.createIter();
		ret.setValue(iter, 0, s);
	}
	return ret;
}




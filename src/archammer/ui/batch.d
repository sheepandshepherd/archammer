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

module archammer.ui.batch;

import std.conv : to, text;
import std.string : toStringz, fromStringz;
import std.traits : EnumMembers;

debug import std.stdio;

import archammer.ui.util;
import archammer.util;
import archammer.arc3do;
import archammer.arcpal;
import archammer.arcbm;

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
import gtk.Entry;

import glib.ListG, glib.ListSG;
import gio.FileIF;
import gtk.FileFilter;
import gobject.Value;
import gtk.ListStore;
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
		headerOutputDirectory.setActive(0);
		
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
		fileChooser.addFilter(FileFilters.all);
		fileChooser.addFilter(FileFilters.assimp);
		fileChooser.addFilter(FileFilters.arc3do);
		fileChooser.setModal(true);
		fileChooser.setLocalOnly(true);
		
		auto response = fileChooser.run();
		if(response == ResponseType.OK)
		{
			import std.algorithm.iteration;
			import std.range : array;
			import glib.ListSG;
			import gio.File, gio.FileIF;
			/// load each
			auto list = fileChooser.getFiles();
			scope(exit) list.free(); /// ObjectGs get `unref`ed by the D destructor.
			File[] files = list.toArray!File();
			
			string[] paths = files.map!(f=>f.getPath()).array;
			
			fileChooser.hide();
			
			foreach(f; paths)
			{
				import std.file : exists;
				if(f.exists)
				{
					openFile(f);
				}
			}
			
			
			files.each!(f=>(object.destroy(f)));
		}
	}
	
	/// Open a file from a path, determine its type, and add it to a FileEntry in the Batch UI if successful.
	void openFile(string filePath)
	{
		import std.path, std.file;
		import std.uni : icmp;
		try
		{
			auto ext = extension(filePath);
			if(  FileFilters.arc3do.matchFile(filePath)  )
			{
				auto arc3do = Arc3do.load3do(filePath);
				auto fe = addFile(new File3do(filePath, arc3do));
				fe.outputType.setActive(2); // default to OBJ export
			}
			else if( FileFilters.assimp.matchFile(filePath) )
			{
				auto arc3do = Arc3do.loadMesh(filePath);
				auto fe = addFile(new File3do(filePath, arc3do));
				fe.outputType.setActive(1); // default to 3DO export
			}
		}
		catch(Exception e)
		{
			showErrorDialog("Load exception", "Error loading file <"~filePath~">:", e.msg);
		}
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
		File file;
		uint outputFormat = 0;
		
		Image thumbnail;
		Entry name;
		
		ComboBox outputType;
		Button convertButton;
		
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
			string nameText = file.path?file.baseName:"new";
			name = new Entry(nameText,8);
			auto viewButton = new Button("View");
			viewButton.setSensitive(false);
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
			outputType = new ComboBox(file.outputList(),false);
			
			convertButton = new Button("Save");
			convertButton.setName("saveFile"); // green background
			convertButton.addOnClicked( (b)=>convert() );
			
			auto outputTypeCell = new CellRendererText();
			outputType.packStart(outputTypeCell, false);
			outputType.addAttribute(outputTypeCell, "text", 0);
			outputType.setTitle("Format");
			outputType.setTooltipText("File format to save in (or blank to leave this file unmodified)");
			outputType.addOnChanged(delegate void(ComboBox c)
				{
					convertButton.setSensitive(c.getActive() != 0);
				});
			outputType.setActive(0);
			
			outBox.packStart(outputType, true, true, 2);
			outBox.packStart(convertButton, false, false, 2);
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
			
		}
	}
	
	
	
	
	
	
}




/// File data for batch window
abstract class File
{
	abstract pure @property string type(); /// the file type (not format)
	abstract pure @property const(string[]) outputTypes();
	abstract @property ListStore outputList();
	immutable string path; // input path, or null if it's a new file
	@property string baseName()
	{
		import std.path;
		if(path is null) return null;
		return stripExtension(baseName(path));
	}
	
	@disable this(); /// no default constructor because we need to set immutable `path`
	this(string path)
	{
		this.path = path;
	}
	
	/// Save the file.
	/// params:
	/// 	name = the filename without directories or extension to use for saving
	/// 	format = the id of the file format to save in (from the formats specified in outputTypes)
	/// 	local = whether to save in the same directory as the input. Otherwise, file is saved in Arc Hammer output directory.
	void save(string name, int format, bool local = true);
}

class File3do : File
{
	static this()
	{
		_outputList = createStringListStore(_outputTypes);
	}
	static immutable(string[]) _outputTypes = ["","3DO (Dark Forces)","OBJ"];
	static ListStore _outputList;
	override pure @property string type() { return "Mesh"; }
	override pure @property const(string[]) outputTypes() { return _outputTypes; }
	override @property ListStore outputList() { return _outputList; }
	
	Arc3do file;
	
	this(string path, Arc3do file)
	{
		super(path);
		this.file = file;
		
		// TODO: generate OpenGL stuff
	}
	
	override void save(string name, int format, bool local = true)
	{
		if(format == 0) return; // no format set
		debug writeln("Saving \"",name,"\" of format ",format,(local?" locally":" in ArcHammer dir"));
		import std.path, std.file;
		import std.string : toUpper;
		string savePath;
		if(local && path !is null)
		{
			savePath = buildPath(path.dirName, name.toUpper);
		}
		else
		{
			savePath = buildPath(thisExePath.dirName, name.toUpper);
		}
		
		switch(format)
		{
		case 1: /// 3DO
			savePath = savePath.setExtension("3DO");
			if(exists(savePath)) remove(savePath);
			debug writeln(savePath);
			write(savePath, file.data());
			break;
		case 2: /// OBJ
			savePath = savePath.setExtension("OBJ");
			if(exists(savePath)) remove(savePath);
			debug writeln(savePath);
			write(savePath, file.wavefrontObj());
			break;
		default: /// invalid format, or 0/"blank" selected
			
			break;
		}
	}
	
	/// TODO: OpenGL handles for this object. Generate at load so we can display in the View3do tab
}

class FilePal : File
{
	static this()
	{
		_outputList = createStringListStore(_outputTypes);
	}
	static immutable(string[]) _outputTypes = ["","PAL (Dark Forces)","GPL (Gimp)"];
	static ListStore _outputList;
	override pure @property string type() { return "Palette"; }
	override pure @property const(string[]) outputTypes() { return _outputTypes; }
	override @property ListStore outputList() { return _outputList; }
	
	ArcPal file;
	
	this(string path, ArcPal file)
	{
		super(path);
		this.file = file;
	}
	
	override void save(string name, int format, bool local = true)
	{
		if(format == 0) return; // no format set
		import std.path, std.file;
		import std.string : toUpper;
		string savePath;
		if(local && path !is null)
		{
			savePath = buildPath(path.dirName, name.toUpper);
		}
		else
		{
			savePath = buildPath(thisExePath.dirName, name.toUpper);
		}
		
		switch(format)
		{
		case 1: /// PAL
			savePath = savePath.setExtension("PAL");
			if(exists(savePath)) remove(savePath);
			debug writeln(savePath);
			write(savePath, file.data());
			break;
		case 2: /// Gimp
			savePath = savePath.setExtension("GPL");
			if(exists(savePath)) remove(savePath);
			debug writeln(savePath);
			write(savePath, file.gimp());
			break;
		default: /// invalid format, or 0/"blank" selected
			
			break;
		}
	}
	
	/// TODO: OpenGL handles for this object. Generate at load so we can display in the View3do tab
}

class FileBm : File
{
	static this()
	{
		_outputList = createStringListStore(_outputTypes);
	}
	static immutable(string[]) _outputTypes = ["","BM","BMP","PNG","JPG","GIF"];
	static ListStore _outputList;
	override pure @property string type() { return "Texture"; }
	override pure @property const(string[]) outputTypes() { return _outputTypes; }
	override @property ListStore outputList() { return _outputList; }
	
	//ArcBm file;
	this(string path)//, ArcBm file)
	{
		super(path);//this.path = path;
		//this.file = file;
	}
	
	override void save(string name, int format, bool local = true)
	{
		// TODO
	}
	
	/// TODO: freeimage handles
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




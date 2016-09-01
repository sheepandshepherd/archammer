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

module archammer.ui.executor;


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




class Executor : Box, ArcTab
{
	ArcWindow window;


	Box modBox;

	this(ArcWindow window)
	{
		super(Orientation.VERTICAL, 4);

		this.window = window;

		auto header = new Box(Orientation.HORIZONTAL, 4);
		packStart(header,false,false,4);

		auto launchDosBoxButton = new Button("Play Dark Forces >");
		launchDosBoxButton.setTooltipText("Launch DF through DosBox without any mods");
		launchDosBoxButton.addOnClicked((Button b){ launchDosBox(null); });
		header.add(launchDosBoxButton);


		modBox = new Box(Orientation.VERTICAL, 2);
		auto modScroll = new ScrolledWindow(modBox);
		modScroll.setPolicy(GtkPolicyType.NEVER, GtkPolicyType.AUTOMATIC);
		auto modFrame = new Frame(modScroll, null);
		packStart(modFrame,true,true,0);
	}

	~this()
	{
		clearModInfoCache();
	}


	private void clearModInfoCache()
	{
		auto vs = modInfoCache.values;
		foreach(ModInfo mi; vs)
		{
			Mallocator.instance.dispose(mi);
		}
		modInfoCache = null;
		assert(modInfoCache.length == 0);
	}


	private ModInfo[string] modInfoCache; /// chache for ModInfo, cleared on refresh of mod list
	private ModFrame[] modFrames = []; /// storage for the ModFrames so we don't have to use GTK's problematic ListGs

	private class ModFrame : Frame
	{
		ModInfo info;
		this(string mod, ModInfo info)
		{
			this.info = info;

			auto box = new Box(Orientation.HORIZONTAL, 2);
			box.setBorderWidth(2);
			super(box, mod);
			
			auto thumbnail = new Image();
			thumbnail.setFromIconName("document-open", IconSize.DIALOG); // 48px
			box.packStart(thumbnail,false,false,2);
			
			if(info.gob !is null) // if there's a GOB present in the folder at all
			{
				auto playDosBox = new Button("Play >");
				playDosBox.setTooltipText("Launch this mod through DosBox");
				playDosBox.addOnClicked((Button b){ launchDosBox(info); });
				box.packStart(playDosBox,false,false,2);
			}
		}
	}
	
	private void addModEntry(string mod)
	{
		ModInfo info = makeModInfo(mod);
		auto entry = new ModFrame(mod, info);
		modFrames ~= entry;
		modBox.add(entry);
	}

	/// Internal data about a mod folder needed for launching the mod
	static class ModInfo
	{
		string dir; /// own directory within the DARK/mods/ directory
		string gob; /// name of the gob to be passed to DARK.EXE
		string dfbrief; /// name of the LFD to replace DFBRIEF.LFD
		string[] otherFiles; /// some mods (Dark Tide 1-3) have a non-briefing LFD that needs to be copied like the gob.
		string icon; /// name of image file in mod folder to use as a thumbnail icon
	}

	/// generate ModInfo corresponding to a mod name and add it to the cache
	private ModInfo makeModInfo(string mod)
	{
		import std.file, std.path;
		import std.uni : icmp;
		import std.range : array;

		ModInfo info = Mallocator.instance.make!ModInfo();
		assert(modInfoCache.get("mod",null) is null);
		modInfoCache[mod] = info;

		string darkDir = window.settings.darkExeEntry.getText().dirName;
		info.dir = buildPath(darkDir,"mods",mod);

		auto gobsInMod = dirEntries(info.dir,SpanMode.shallow).filter!(de => icmp(de.name.extension, ".gob")==0);
		if(!gobsInMod.empty)
		{
			info.gob = gobsInMod.front.name.baseName;
		}

		auto lfdsInMod = dirEntries(info.dir,SpanMode.shallow).filter!(de => icmp(de.name.extension, ".lfd")==0).array;
		if(lfdsInMod.length == 1)
		{
			info.dfbrief = lfdsInMod[0].name.baseName;
		}
		else if(lfdsInMod.length > 1)
		{
			import std.algorithm.searching, std.uni, std.string;
			/// TODO: better way to determine the briefing file would be to open the LFDs and check for briefings.
			/// until there's an LFD loader, pick the one that contains the word "brief"
			auto index = lfdsInMod[].countUntil!((DirEntry lfd) =>
				(   indexOf(lfd.name.baseName, "brief", CaseSensitive.no) != -1   ));
			if(index == -1)
			{
				window.batch.showErrorDialog("LFD Error", mod,
					"This mod contains multiple LFDs, but the briefing file couldn't be determined.");
				foreach(de; lfdsInMod[]) info.otherFiles ~= de.name.baseName;
			}
			else
			{
				info.dfbrief = lfdsInMod[index];
				foreach(li, de; lfdsInMod[])
				{
					if(li != index) info.otherFiles ~= de.name.baseName;
				}
			}
		}

		return info;
	}





	/// RAII struct for backing up DFBRIEF.LFD and other files from the DARK folder when running a mod.
	/// Backed-up files are restored and modGob is removed when the struct is destroyed.
	static struct BackupFiles
	{
		import std.file, std.path;

		string darkDir; /// DARK.EXE's directory; also where the files are kept and the parent of the mods directory.
		string[] filesToDelete; /// mod's files to delete before restoring backups
		bool leaveDFBrief; /// do nothing with DFBRIEF.LFD; for mods that don't want to replace it

		@disable this();
		@disable this(this);
		this(string darkDir, string modGob, bool leaveDFBrief, string[] otherFiles)
		{
			if(!exists(darkDir)) throw new FileException(darkDir,"Dark Forces directory does not exist!");

			this.darkDir = darkDir;
			this.leaveDFBrief = leaveDFBrief;
			filesToDelete = [modGob, "DRIVE.CD"];
			if(!leaveDFBrief) filesToDelete ~= "DFBRIEF.LFD";
			if(otherFiles !is null) filesToDelete ~= otherFiles;

			string modsDir = buildPath(darkDir,"mods");
			if(!exists(modsDir)) mkdir(modsDir);
			string backupDir = buildPath(modsDir,"backup");
			if(!exists(backupDir)) mkdir(backupDir);

			foreach(DirEntry de; dirEntries(darkDir,SpanMode.shallow))
			{
				if(de.isDir) continue; // don't bother checking directories

				// need to do case insensitive comparison for Posix compatibility
				if( filenameCmp!(CaseSensitive.no)(de.name.baseName, "DRIVE.CD") == 0 ||
					(!leaveDFBrief && filenameCmp!(CaseSensitive.no)(de.name.baseName, "DFBRIEF.LFD") == 0) )
				{
					rename(de.name, buildPath(backupDir, de.name.baseName));
				}
			}

		}

		~this()
		{
			import std.file, std.path;

			debug writeln("Removing: ",filesToDelete);
			debug writeln("Restoring backups...");

			// remove own files, including DFBRIEF.LFD if it's in the list
			// This should work on case-sensitive Posix because the files were copied using the same case as in the list
			foreach(f; filesToDelete)
			{
				remove(buildPath(darkDir, f));
			}

			// return all files in backupDir back to darkDir
			string backupDir = buildPath(darkDir,"mods","backup");
			foreach(DirEntry de; dirEntries(backupDir,SpanMode.shallow))
			{
				rename(de.name, buildPath(darkDir, de.name.baseName));
			}


		}
	}

	/// clear and regenerate modBox based on current DF directory
	void refreshModList()
	{
		import std.path, std.file;
		import std.uni : icmp;
		import std.algorithm.sorting : sort;
		import std.range : array;

		foreach(mfi; 0..modFrames.length)
		{
			ModFrame mf = modFrames[mfi];
			mf.destroy(); // gtk destroy
			object.destroy(mf);
		}
		modFrames.length = 0;
		clearModInfoCache();

		string darkDir = window.settings.darkExeEntry.getText().dirName;
		string modsPath = buildPath(darkDir,"mods");
		if(isValidPath(modsPath) && exists(modsPath))
		{
			auto dirs = dirEntries(modsPath, SpanMode.shallow).array
				.sort!((DirEntry a, DirEntry b)=>(icmp(a.name.baseName, b.name.baseName)<0));

			foreach(de; dirs) if(de.isDir)
			{
				if(icmp(de.name.baseName, "backup")==0) continue;
				string mod = de.name.baseName;
				addModEntry(mod); // generate the ModInfo and the frame
			}

			modBox.showAll();
		}
	}

	/// Show details of a mod (like what levels it contains and the briefings in the LFD)
	void viewDetails(string mod)
	{

	}

	/// Launch with DosBox
	void launchDosBox(ModInfo info)
	{
		import std.file, std.path;
		import std.process : execute, executeShell;
		import std.format : format;
		import std.uni : icmp;
		import std.string : join;

		string darkExe = window.settings.darkExeEntry.getText();
		if(!darkExe.isValidPath || !darkExe.exists) return;
		string darkDir = window.settings.darkExeEntry.getText().dirName; /// the directory DARK.EXE is in

		/// dosbox "darkDir/DARK.EXE" -c "mount D: cdDir/" -exit
		if(info is null)
		{
			// launch vanilla DF without any file copies
			string[] proc = [
				window.settings.dosBoxExeEntry.getText(),
				format(`"%s"`,darkExe),
				format(`-c "mount D %s"`, window.settings.darkCDEntry.getText()),
				"-exit"
			];

			/// TODO: make it a setting
			if(window.settings.fullscreenCheck.getActive()) proc ~= "-fullscreen";

			auto cmd = proc.join(" ");
			debug writeln("Executing: ", cmd);
			executeShell(cmd);
		}
		else
		{
			assert(info.gob !is null, "No GOB in the mod's folder"); // GOB is required

			// create the backups; this struct will automatically restore the files upon destruction.
			BackupFiles backupFiles = BackupFiles(darkDir, info.gob, info.dfbrief is null, info.otherFiles);

			// copy the GOB and LFD (the backup struct will remove both copies afterwards)
			copy(buildPath(info.dir,info.gob), buildPath(darkDir,info.gob));
			if(info.dfbrief !is null) copy(buildPath(info.dir,info.dfbrief), buildPath(darkDir,"DFBRIEF.LFD"));
			if(info.otherFiles !is null) foreach(f; info.otherFiles)
			{
				copy(buildPath(info.dir,f), buildPath(darkDir,f));
			}

			// and create DRIVE.CD to point to D drive
			write(buildPath(darkDir, "DRIVE.CD"),['D']);

			/// dosbox -c "mount D: cdDir/" -c "mount C: darkDir/" -c "C:" -c "DARK.EXE -u~.gob" -c "exit"
			string[] proc = [
				window.settings.dosBoxExeEntry.getText(),
				format(`-c "mount D %s"`, window.settings.darkCDEntry.getText()),
				format(`-c "mount C %s"`, darkDir),
				`-c "C:"`,
				format(`-c "DARK.EXE -u%s"`, info.gob),
				`-c "exit"`
			];

			/// TODO: make it a setting
			if(window.settings.fullscreenCheck.getActive()) proc ~= "-fullscreen";

			auto cmd = proc.join(" ");
			debug writeln("Executing: ", cmd);
			executeShell(cmd);
		}
	}

	/// Launch with DarkXL
	void launchDarkXL(string mod)
	{

	}



	override void updateTab()
	{
		refreshModList();
	}

}







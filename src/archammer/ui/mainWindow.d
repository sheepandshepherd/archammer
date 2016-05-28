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

module archammer.ui.mainWindow;

debug import std.stdio : writeln;

import gtk.Dialog, gtk.FileChooserDialog, gtk.FileChooserIF;
import gtk.Main;
import gtk.MainWindow;
import gtk.Menu;
import gtk.MenuBar;
import gtk.MenuItem;
import gtk.Widget;
import gdk.Event;
import gtk.Label;
import gtk.Button;
import gtk.ProgressBar;
import gtk.Box;
import gtk.Notebook;
import gtk.Statusbar;

import gtk.CssProvider;
import gtk.StyleContext;
import gdk.Display;
import gdk.Screen;

import gtk.DragAndDrop, gtk.TargetList, gtk.TargetEntry, gdk.DragContext, gtk.SelectionData;

import archammer.ui.util;
import archammer.ui.batch;
import archammer.ui.tabbm, archammer.ui.tabgob;

class ArcWindow : MainWindow
{
	Statusbar status;
	Batch batch;
	TabBm tabBm;
	TabGob tabGob;
	this()
	{
		super("Arc Hammer");
		
		setDefaultSize(800, 800);
		
		auto display = Display.getDefault();
		auto screen = display.getDefaultScreen();
		
		auto cssProvider = new CssProvider();
		StyleContext.addProviderForScreen(screen, cssProvider, 600); //GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600. how to get this in GTKD?
		cssProvider.loadFromData(arcCss);

		auto targetEntries = [new TargetEntry("text/uri-list", TargetFlags.OTHER_APP, 0)];

		dragDestSet(DestDefaults.ALL,targetEntries,DragAction.COPY | DragAction.MOVE | DragAction.PRIVATE);
		addOnDragDrop(&this.dndDrop);
		addOnDragDataReceived(&this.dndDataReceived);
		
		MenuBar menuBar = new MenuBar();
		
		menuBar.append(new FileMenu);
		menuBar.append(new HelpMenu(this));
		
		auto box = new Box(Orientation.VERTICAL, 0);
		box.packStart(menuBar, false, false, 0);
		
		auto tabs = new Notebook;
		
		batch = new Batch(this);
		tabs.appendPage(batch, "Batch");

		tabGob = new TabGob(this);
		tabs.appendPage(tabGob, "GOB");
		
		tabBm = new TabBm(this);
		tabs.appendPage(tabBm, "BM");
		
		tabs.addOnSwitchPage(delegate void(Widget w, uint p, Notebook n)
		{
			ArcTab tab = cast(ArcTab)w;
			if(tab)
			{
				tab.updateTab();
			}
		});
		
		box.packStart(tabs, true, true, 0);
		status = new Statusbar;
		box.packStart(status, false, false, 0);
		add(box);
		showAll();
	}
	
	/// Drag and Drop on main window
	bool dndDrop(DragContext dc, int x, int y, uint time, Widget w)
	{
		debug writeln("dndDrop()");
		return true;
	}

	///
	void dndDataReceived(DragContext dc, int x, int y, SelectionData data, uint info, uint time, Widget w)
	{
		import glib.URI;
		import std.path, std.file;
		debug writeln("dndDataReceived()");
		if(info == 0) // make sure it's an external file
		{
			string[] uris = data.getUris();
			assert(uris !is null, "BUG: Non-URI data dropped on window; not sure how to handle it. Should ignore?");
			if(uris.length == 0)
			{
				writeln("BUG: No files in URI drop; reason unknown.");
				dc.dropFinish(dc, false, time);
				return;
			}
			foreach(u; uris)
			{
				string hostname;
				auto f = URI.filenameFromUri(u,hostname);
				if(f.exists)
				{
					ubyte[] fdata = cast(ubyte[])read(f);
					batch.openFile(f, fdata);
				}
			}

			dc.dropFinish(dc, true, time);
			return;
		}

		dc.dropFinish(dc, false, time);
		return;
	}
	
	
	class FileMenu : MenuItem
	{
		
		Menu menu;
		MenuItem openMenuItem;
		MenuItem exitMenuItem;
		
		this()
		{
			super("File");
			menu = new Menu();
			
			openMenuItem = new MenuItem("Open...");
			openMenuItem.addOnActivate( m=>batch.showLoadFileDialog() );
			menu.append(openMenuItem);
			
			exitMenuItem = new MenuItem("Exit");
			exitMenuItem.addOnActivate( m=>Main.quit() );
			menu.append(exitMenuItem);
			
			setSubmenu(menu);
		}
	}

	class HelpMenu : MenuItem
	{
		import gtk.AboutDialog;
		
		ArcWindow mw;
		Menu menu;
		MenuItem aboutMenuItem;
		
		this(ArcWindow mw)
		{
			this.mw = mw;
			super("Help");
			menu = new Menu();
			
			aboutMenuItem = new MenuItem("About");
			aboutMenuItem.addOnButtonRelease(&aboutEvent);
			menu.append(aboutMenuItem);
			
			setSubmenu(menu);
		}
		
		bool aboutEvent(Event event, Widget widget)
		{
			import std.stdio;
			writeln("aboutEvent");
			menu.popdown();
			///import gtk.Window;
			auto about = new AboutDialog();
			about.setTransientFor(mw);
			about.setModal(true);
			about.setProgramName("Arc Hammer");
			about.setComments("File converter tool for Dark Forces");
			about.setVersion("0.0.1 (3DO)");
			about.setAuthors(["sheepandshepherd"]);
			about.setLicenseType(GtkLicense.GPL_2_0);
			about.setWebsite("https://github.com/sheepandshepherd/archammer");
			about.setWebsiteLabel("Source code");
			
			about.run();
			about.destroy();
			return true;
		}
	}
	
	
	
	const string arcCss = `.button#closeFile {
	background-image: linear-gradient(to bottom, #faa, #e88);
}
.button#closeFile:active {
	background-image: linear-gradient(to bottom, #f88, #e55);
}
.button#closeFile:insensitive {
	background-image: linear-gradient(to bottom, #fdd, #ebb);
}
.button#saveFile {
	background-image: linear-gradient(to bottom, #afa, #8e8);
}
.button#saveFile:active {
	background-image: linear-gradient(to bottom, #8f8, #5e5);
}
.button#saveFile:insensitive {
	background-image: linear-gradient(to bottom, #dfd, #beb);
}`;
	
}












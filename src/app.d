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

import std.stdio;

import std.string : icmp;
import std.conv : text;

import archammer.util;
import archammer.arc3do;

import gtk.Main, gtk.MainWindow;

import archammer.ui.util;
import archammer.ui.mainWindow;



void main(string[] args)
{
	arcInit();
	debug writeln("Starting ArcHammer GTK-D UI...");
	Main.init(args);
	auto window = new ArcWindow();
	Main.run();
}

/// set up Derelict bindings, dynamic libraries, etc.
void arcInit()
{
	import derelict.util.exception, derelict.util.loader;
	//import derelict.opengl3.gl3;
	import derelict.assimp3.assimp;
	//import derelict.freeimage.freeimage;
	
	import gtk.FileFilter;

	debug writeln("arcInit()");

	try{
		//DerelictGL3.load();
		//DerelictGLFW3.load();
		DerelictASSIMP3.load();
		//DerelictFI.load(SharedLibVersion(3, 15, 4));
	}
	catch(DerelictException de)
	{
		writeln("Failed to load Derelict libs: ",de.msg);
		throw new Exception("Failed to load Derelict libs: "~de.msg);
	}
	
	/// create FileFilters for GTK+ file dialogs
	FileFilters.init();
}

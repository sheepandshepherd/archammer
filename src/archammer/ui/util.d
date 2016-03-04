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

/// Arc Hammer UI utilities
module archammer.ui.util;

debug import std.stdio : writeln;

import gtk.FileFilter;

class ArcFilter : FileFilter
{
	string[] patterns = [];
	void add(string pattern)
	{
		addPattern(pattern);
		patterns ~= pattern;
	}
	bool matchFile(string filePath)
	{
		import std.path : globMatch;
		foreach(p; patterns)
		{
			if(filePath.globMatch(p)) return true;
		}
		return false;
	}
}

static class FileFilters
{
static:
	ArcFilter all; /// *.*
	ArcFilter assimp; /// all mesh types importable by ASSIMP
	ArcFilter arc3do; /// DF 3DO
	ArcFilter obj; /// wavefront OBJ
	
	void init()
	{
		import derelict.assimp3.assimp, derelict.assimp3.types;
		import std.algorithm.iteration : splitter, map, each, joiner;
		import std.uni : isAlpha, toUpper, toLower;
		import std.utf : toUTF8;
		import std.range : chain, array, only, choose;
		
		all = new ArcFilter();
		all.setName("All Files - *.*"); // extension required for determining file type
		all.add("*.*");
		
		assimp = new ArcFilter();
		assimp.setName("Mesh (ASSIMP) - *.OBJ; *.DAE; etc");
		aiString assimpString;
		aiGetExtensionList(&assimpString); /// TODO: memory management? not sure who owns this now
		string assimpExtensionList = assimpString.data[0..assimpString.length].idup;
		debug writeln("ASSIMP Ext list: ", assimpExtensionList);
		
		/// splitter(';') the extension list, replace alpha chars with "[aA]", feed each to assimp.addPattern
		auto splitted = assimpExtensionList.splitter(';');
		auto patterns = splitted.map!( ext => joiner(ext.map!( ch => choose(ch.isAlpha,chain("[",[ch.toLower].toUTF8,[ch.toUpper].toUTF8,"]"),ch.only) )) );
		debug writeln("ASSIMP Patterns: ",patterns.array);
		
		patterns.each!(p => assimp.add( p.array.toUTF8 ));
		
		arc3do = new ArcFilter();
		arc3do.setName("Mesh (Dark Forces 3DO) - *.3DO");
		arc3do.add("*.3[dD][oO]");
		
		obj = new ArcFilter();
		obj.setName("Mesh (Wavefront OBJ)");
		obj.add("*.[oO][bB][jJ]");
	}
}





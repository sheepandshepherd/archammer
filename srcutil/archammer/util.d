/+
This file is part of the Arc Hammer subpackages, mod libraries for Dark Forces.
Copyright (C) 2016  sheepandshepherd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
+/

module archammer.util;

import std.traits;

/// ParseTree navigation convenience function.
/// Gets subnodes of $(PARAM p) recursively by the specified $(PARAM indices).
/// 
/// Examples:
/// -----
/// ParseTree subTree = p.ch(3,2,1); // equivalent to p.children[3].children[2].children[1]
/// -----
/// 
/// Params:
/// 	p = the ParseTree to navigate
/// 	indices = variadic array of child indices to navigate
/// 
/// Returns: the subnode, if found, or ParseTree() if any indices are out of bounds.
nothrow TreeType ch(TreeType)(TreeType p, size_t[] indices ...)
if( is(TreeType == struct) && hasMember!(TreeType, "children") ) // duck-typing ParseTree is questionable, but allows dropping Pegged dependency in arcutil.
{
	TreeType pc = p;
	foreach(n; indices)
	{
		if(pc.children is null) return TreeType();
		if(pc.children.length <= n) return TreeType(); // null tree
		pc = pc.children[n];
	}
	return pc;
}




/// Preprocesses line comments out of a piece of source material.
/// The comments are assumed to start with $(PARAM commentsString) and end with any newline.
/// params:
/// 	commentsString = The set of characters initiating a line comment
/// 	content = The string from which to remove comments
nothrow string preprocessLineComments(string commentsString = "#")(string content)
{
	import std.conv : text;
	import std.algorithm.searching : findSplitBefore, findSkip, find;
	import std.range : join, empty;
	auto rb = findSplitBefore(content, commentsString);
	while(!rb[1].empty) // else: no comment found, finished!
	{
		// comment found. advance to next nearest newline
		/// TODO: use countUntil instead, it's better
		//if(!rb[1].findSkip("\r\n")) if(!rb[1].findSkip("\n")) if(!rb[1].findSkip("\r"))
		string rc = rb[1].find("\r\n");
		if(rc.empty)
		{
			rc = rb[1].find("\n");
			if(rc.empty)
			{
				rc = rb[1].find("\r");
				// if no newline found, trim the rest of the file
			}
		}
		rb = findSplitBefore((rb[0]~rc),commentsString);
	}
	
	return text(rb[0]);
}


/++
Dark Forces Color
Each component (r,g,b,a) is a 6-bit compessed ubyte, ranging 0..64, as in DF.
Also, the 8-bit field `index` points to a palette color in paletted textures.
+/
struct Color
{
	import std.bitmanip, std.meta;
	mixin(bitfields!(
		ubyte, "r", 6,
		ubyte, "g", 6,
		ubyte, "b", 6,
		ubyte, "a", 6,
		ubyte, "index", 8
	));
	
	alias components = AliasSeq!(r, g, b, a, index);
	
	ubyte opIndex(size_t component) const
	{
		return [components][component];
	}
	void opIndexAssign(ubyte value, size_t component)
	{
		[components][component] = value;
	}
	
	this(ubyte r, ubyte g, ubyte b, ubyte a, ubyte index)
	{
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
		this.index = index;
	}
}






/++
Generic save format for files
+/
struct SaveFormat
{
	string extension; /// filename extension
	string name; /// name of the format displayed in the UI
	void[] delegate() dataFunction; /// the function to call when saving
}


interface Savable
{
	@property const(SaveFormat[]) saveFormats();
}




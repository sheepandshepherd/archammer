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

module archammer.arcpal;

import archammer.util;

debug import std.stdio : writeln;

//import derelict.freeimage.freeimage;
/++
 + A static palette.
 + 
 +/
class ArcPal : Savable
{
	string name = "pal";
	Color[256] palette;
	
	@property const(SaveFormat[]) saveFormats() { return [
		SaveFormat("PAL","PAL (Dark Forces)",&data),
		SaveFormat("GPL","GPL (Gimp)", cast(void[] delegate()) &gimp )  ]; }

	/// TODO: RGB comparison is primitive. Convert to HSL or better algorithm instead.
	ubyte mostSimilarIndex(in Color color)
	{
		import std.math : abs;
		ubyte index = 0;
		ushort diff = ushort.max;
		foreach(i; 0..256)
		{
			ushort comp = 0;
			foreach(ci; 0..3)
			{
				comp += abs(color[ci]-palette[i][ci]);
			}
			if(comp < diff)
			{
				index = cast(ubyte)i;
				diff = comp;
			}
		}
		return index;
	}
	
	void[] data()
	{
		ubyte[] ret = new ubyte[768];
		foreach(ci, c; palette)
		{
			foreach(cic; 0..3)
			{
				ret[3*ci+cic] = c[cic];
			}
		}
		return ret;
	}

	/// converted to GIMP's palette format
	string gimp()
	{
		import std.array : appender, Appender;
		import std.conv : text;
		auto ret = appender!string("GIMP Palette\nName: ");
		ret.put(name);
		ret.put("\nColumns: 16\n#\n");
		foreach(c; palette)
		{
			foreach(ci; 0..3)
			{
				ubyte color = cast(ubyte)(4*c[ci]); // GIMP colors are normal 0..256, not DF's 0..64
				if(color < 100) ret.put(" ");
				if(color < 10) ret.put(" ");
				ret.put(text(color));
				ret.put(" ");
			}
			ret.put("Untitled\n");
		}
		return ret.data;
	}

	static ArcPal load(string filePath)
	{
		import std.stdio : writeln;
		import std.file;
		if(!exists(filePath)) throw new FileException(filePath~" does not exist.");
		
		void[] content = read(filePath);
		
		return loadData(cast(ubyte[])content);
	}

	static ArcPal loadData(in ubyte[] data)
	{
		import std.conv : to;
		if(data is null || data.length != 768) throw new Exception("Invalid PAL data; must be array of 768 bytes");

		auto ret = new ArcPal();
		foreach(ci; 0..256)
		{
			ret.palette[ci] = Color(data[3*ci], data[3*ci+1], data[3*ci+2], 63, cast(ubyte)ci);
		}
		return ret;
	}

	this()
	{

	}

	private static ArcPal loadB64(in string b64)
	{
		import std.base64;
		return loadData(Base64.decode(b64));
	}
	static const ArcPal secbase = loadB64("AAAAPz8/NDs/Kjc/HzM/FTA/PwAAMwAAJAAAEQAAAD8AADIAACYAABcAAA0AABY/AAk8AAQvAAEjPjgYPS4NPSIDNhYDLQsBPwA/PwA/PwA/PwA/PwA/PwA/PwA/PwA/Ojo6ODg4NjY2NDQ0MzMzMTExLy8vLS0tKysrKioqKCgoJiYmJCQkIyMjISEhHx8fHR0dHBwcGhoaGRkZFxcXFhYWFBQUExMTEREREBAQDg4ODQ0NCwsLCgoKCAgIBwcHGRshFxkeFRccExUaEhMYEBEVDhATDQ4RCwwPCQoMBwgKBgYIBAQGAgMDAQEBAAAAPzksOzQmNzAhNCwdMCgYLSQUKSERJR0NIhkKHhYHGxMFFxADEw0CEAoBDAcACQUAOBsDNRkCMhcCLxYBLBQBKhIBJxEBJA8BIQ4AHg0AHAsAGQoAFggAEwcAEAYADgUAIDkZHDUVGTIRFy8OFCwLESkIDyUGDSIDCx8CCRwACBkADBUBDhIBDg4CCwoCCAYCPzUyPTEtPC4pOislOCghNyUdNSIaNCAXMh0TMRsQLxkNLhcKLBUIKxQFKRIDKBEBJRcAIhMAHw8AHAwAGgkAFwcAFAQAEgMAAAA/AAA4AAAyAAAsAAAlAAAfAAAZAAATPwAAOAAAMQAAKgAAIwAAHAAAFQAADgAAPyAAOBsAMhcALBMAJg8AIAsAGggAFAYAMBwRLRoPKhgOJxYNJRUMIhMLHxEJHRAIGg4HFwwGFAsFEgkEDwgDDAYCCgUCDwgELjo/Kjg+Jzc+IzU9IDM8HTE8GTA7Fi47Eyw6ECs6DSk5Cic5ByU4BCM4ASI3ACA3GRshGBogFxkeFhgdFRccFBYbFBUaExQZEhMYERMXEBIWDxEVDxAUDg8SDQ4RDA0QCwwPCgsOCgsNCQoMCAkLBwgKBgcJBgYIBQUGBAQFAwMEAgIDAQICAQEBAAAAAAAAAAAkAAAhAAAeAAAcAAAZAAAWAAAUAAARAAAPAAAMAAAJAAAHAAAEAAABAAAAPz8/");
}

class ArcCmp
{

}
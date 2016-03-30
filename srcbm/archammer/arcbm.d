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

module archammer.arcbm;

import std.typecons : Tuple;

import derelict.freeimage.freeimage;
//import std.experimental.ndslice;

import archammer.util, archammer.arcpal;

class ArcBm : Savable
{
	@property const(SaveFormat[]) saveFormats() { return [
		SaveFormat("BM","BM (Dark Forces)",&data),
		SaveFormat("GIF","GIF", cast(void[] delegate()) &gif )
		];}
	
	bool transparent = false;
	ubyte transparencyBit = 0; /// on weapons it's 8. otherwise it's 0.
	bool multiple = false;
	enum Compression : ushort { none, rle, rle0 }
	Compression compression = Compression.none;
	size_t w, h;
	union
	{
		Color[] colors; /// color data for a SingleBM (incl compressed)
		SubBm[] subBms; /// subBms in a MultipleBM
	}
	/// TODO
	struct SubBm
	{
		size_t w, h;
		Color[] colors;
	}

	/// hopefully $ref should allow [x,y][ci]=value
	ref Color opIndex(size_t x, size_t y)
	{
		if(multiple) throw new Exception("XY index on multiple BM");
		if(y >= h || x >= w) throw new Exception("XY index out of bounds");
		return colors[h*x+y];
	}

	Color opIndexAssign(Color value, size_t x, size_t y)
	{
		if(multiple) throw new Exception("XY indexAssign on multiple BM");
		if(y >= h || x >= w) throw new Exception("XY indexAssign out of bounds");
		colors[h*x+y] = value;
		return value;
	}
	
	void setPaletteIndicesFromColors(ArcPal palette)
	{
		foreach(x; 0..w) foreach(y; 0..h)
		{
			this[x,y][3] = palette.mostSimilarIndex(this[x,y]);
		}
	}
	
	void setColorsFromPaletteIndices(ArcPal palette)
	{
		foreach(x; 0..w) foreach(y; 0..h)
		{
			foreach(comp; 0..3) this[x,y][comp] = palette[this[x,y].index][comp];
		}
	}

	void[] data()
	{
		import std.array : appender;
		import std.bitmanip;
		import std.math : log2;
		import std.range : repeat, array, retro;
		enum Endian ee = Endian.littleEndian;
		auto ret = appender!(ubyte[])();
		ret.put(cast(ubyte[])[0x42,0x4d,0x20,0x1e]);
		ret.append!(ushort,ee)(cast(ushort)w);
		ret.append!(ushort,ee)(cast(ushort)h);
		ret.append!(ushort,ee)(cast(ushort)w); // unused?
		ret.append!(ushort,ee)(cast(ushort)h); // unused?
		ret.put(cast(ubyte)0x36); /// TODO: weapons 0x8, transparent 0x3E
		ret.put(cast(ubyte)(h.log2));
		ret.append!(ushort,ee)(compression);
		ret.append!(uint,ee)(cast(uint)0x0800); /// TODO: compressed data size
		ret.put(repeat!ubyte(0,12));

		// payload
		if(multiple) return null;
		//else if(compression ==
		else
		{
			// columns, from bottom to top
			foreach(x; 0..w) foreach(y; 0..h) 
			{
				ret.put(this[x,y].index);
			}
		}
		return ret.data;
	}
	
	void[] gif()
	{
		return null;
	}

	/++static ArcBm loadData(ubyte[] data, ArcPal palette = ArcPal.secbase)
	{
		import std.bitmanip;
		
		if(palette is null) return null;
		if(data is null || data.length < 0x20) throw new Exception("Invalid data");
		if(data[0..4] != [0x42,0x4d,0x20,0x1e]) throw new Exception("Not a BM file");



		short w, h;
	}+/

	static ArcBm loadImage(string fileName, ArcPal palette = null)
	{
		import std.file : exists;
		import std.string : toStringz, fromStringz;

		if(!exists(fileName)) return null;

		int format = FreeImage_GetFileType(fileName.toStringz);
		FIBITMAP* imgOrig = FreeImage_Load(format, fileName.toStringz);
		FIBITMAP* img = FreeImage_ConvertTo32Bits(imgOrig);
		FreeImage_Unload(imgOrig);
		int w = FreeImage_GetWidth(img), h = FreeImage_GetHeight(img);

		ArcBm ret = new ArcBm();
		ret.multiple = false;
		ret.w = w;
		ret.h = h;
		ret.colors = new Color[w*h];

		foreach(x; 0..w) foreach(y; 0..h)
		{
			RGBQUAD quad;
			FreeImage_GetPixelColor(img, cast(uint)x, cast(uint)y, &quad);
			ret[x,y][0] = cast(ubyte)(quad.rgbRed/4);
			ret[x,y][1] = cast(ubyte)(quad.rgbGreen/4);
			ret[x,y][2] = cast(ubyte)(quad.rgbBlue/4);
			ret[x,y].a = 63; // default full opacity
		}
		return ret;
	}

	this()
	{

	}
}


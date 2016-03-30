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
debug import std.stdio : writeln;

import derelict.freeimage.freeimage;
//import std.experimental.ndslice;

import archammer.util, archammer.arcpal;

class ArcBm : Savable
{
	@property const(SaveFormat[]) saveFormats() { return [
		SaveFormat("BM","BM (Dark Forces)",&data),
		SaveFormat("PPM6","PPM", &ppm6),
		SaveFormat("GIF","GIF", cast(void[] delegate()) &gif ),
		];}
	
	bool transparent = false;
	ubyte transparencyBit = 0; /// on weapons it's 8. otherwise it's 0.
	bool multiple = false;
	enum Compression : ushort { none = 0, rle = 1, rle0 = 2 }
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
	
	void setPaletteIndicesFromColors(const ArcPal palette)
	{
		foreach(x; 0..w) foreach(y; 0..h)
		{
			this[x,y][3] = palette.mostSimilarIndex(this[x,y]);
		}
	}
	
	void setColorsFromPaletteIndices(const ArcPal palette)
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
	
	void[] ppm6()
	{
		import std.array : Appender;
		import std.conv : text;
		import std.range;
		
		Appender!(ubyte[]) a;
		a.put(cast(ubyte[])text("P6\n",w," ",h,"\n255\n"));
		foreach(y; iota(0,h).retro) foreach(x; 0..w) foreach(c; 0..3) a.put(cast(ubyte)(4*this[x,y][c]));
		return a.data;
	}
	
	void[] gif()
	{
		return null;
	}
	
	static ArcBm load(string filePath)
	{
		import std.stdio : writeln;
		import std.file;
		if(!exists(filePath)) throw new FileException(filePath~" does not exist.");
		
		void[] content = read(filePath);
		
		return loadData(cast(ubyte[])content);
	}

	static ArcBm loadData(ubyte[] data, const ArcPal palette = ArcPal.secbase)
	{
		import std.bitmanip;
		import std.range;
		enum EE = Endian.littleEndian;
		
		if(palette is null) return null;
		if(data is null || data.length < 0x20) throw new Exception("Invalid data");
		if(data[0..4] != [0x42,0x4d,0x20,0x1e]) throw new Exception("Not a BM file");
		
		ubyte[] p = data[4..$];
		
		ArcBm bm = new ArcBm();
		
		// load header:
		bm.w = cast(size_t) p.read!(short, EE);
		bm.h = cast(size_t) p.read!(short, EE);
		p = p.drop(4); // get rid of unused 4 bytes
		bm.transparencyBit = p.read!(ubyte, EE);
		ubyte logSizeY = p.read!(ubyte, EE);
		bm.compression = cast(Compression) p.read!(short, EE);
		size_t length = cast(size_t) p.read!(int, EE);
		p = p.drop(12); // get rid of alignment padding
		
		if(bm.w == 1 && bm.h != 1)
		{
			bm.multiple = true;
			throw new Exception("WIP: MultiBMs are not yet implemented.");
		}
		
		if(bm.compression != Compression.none) throw new Exception("WIP: Compressed BMs are not yet implemented.");
		
		debug writeln(bm.w, "w x ",bm.h,"h; ",length, "l");
		
		// load data:
		if(p.length != bm.w * bm.h) throw new Exception("BM payload does not match size");
		
		bm.colors = new Color[bm.w*bm.h];
		
		foreach(x; 0..bm.w) foreach(y; 0..bm.h)
		{
			bm[x, y].index = p.read!(ubyte, EE);
			bm[x, y].a = 63; // default full opacity
		}
		
		if(palette !is null) bm.setColorsFromPaletteIndices(palette);
		
		return bm;
	}

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
	
	this(size_t w, size_t h, Color[] colors = null)
	{
		this.w = w;
		this.h = h;
		if(colors is null)
		{
			this.colors = new Color[w*h];
		}
		else
		{
			if(colors.length != w*h) throw new Exception("Color array length doesn't match texture size");
			this.colors = colors;
		}
	}
	
	/++
	Returns: a 16x16 texture representing a palette
	+/
	@property static
	ArcBm paletteBm(const ArcPal palette = ArcPal.secbase)
	{
		import std.range;
		ArcBm ret = new ArcBm(16,16);
		size_t ci = 0;
		foreach(y; iota(0,16).retro) foreach(x; 0..16)
		{
			ret[x,y] = palette[ci++];
		}
		return ret;
	}
}


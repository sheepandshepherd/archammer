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

module archammer.arcgob;

import archammer.util;

import std.experimental.allocator.mallocator;
debug import std.stdio : writeln;

import containers.dynamicarray;

class ArcGob : Savable
{
	@property const(SaveFormat[]) saveFormats() { return [ SaveFormat("GOB","GOB (Dark Forces)",&data) ];}
	
	DynamicArray!File files;

	void addFile(in char[] name, in ubyte[] data)
	{
		auto f = new File(name, data);
		files.insert(f);
	}
	
	/++
	Data for a file in a GOB.
	+/
	static class File
	{
		immutable char[] name;
		ubyte[] data;
		
		
		this() @disable;

		/// simple constructor
		@nogc private this(in char[] name, in ubyte[] data)
		body
		{
			char[] nameSlice = cast(char[]) Mallocator.instance.allocate(name.length);
			nameSlice[] = name[];
			this.name = cast(immutable char[])nameSlice;

			this.data = cast(ubyte[])Mallocator.instance.allocate(data.length);
			this.data[] = data[];
		}

		/// constructor for DF GOB entries only
		@nogc private this(in ubyte[] entry, in ubyte[] data)
		in { assert(entry.length == 4+4+13); }
		body
		{
			import std.bitmanip;
			import std.string : fromStringz;
			import std.algorithm.searching;
			
			enum EE = Endian.littleEndian;
			size_t ptr = cast(size_t) entry[0..4].peek!(uint, EE);
			size_t length = cast(size_t) entry[4..8].peek!(uint, EE);
			
			// verify that it's null-terminated before doing anything else with it
			char[] namez = cast(char[])(entry[8..13+8]);
			///if(!namez[].canFind('\0')) throw new Exception("Name field without null terminator");
			
			char[] nameSlice = fromStringz(namez[].ptr);
			nameSlice = cast(char[]) Mallocator.instance.allocate(nameSlice.length);
			nameSlice[] = fromStringz(namez[].ptr)[];
			name = cast(immutable char[])nameSlice;
			
			this.data = cast(ubyte[]) Mallocator.instance.allocate(length);
			this.data[] = data[ptr..ptr+length];
		}
		
		@nogc ~this()
		{
			Mallocator.instance.deallocate(cast(void[])name);
			Mallocator.instance.deallocate(data);
		}
	}
	
	
	/++@nogc+/ /+nothrow+/
	void[] data()
	{
		import std.bitmanip, std.range;
		enum EE = Endian.littleEndian;
		enum char[4] header = "GOB\x0a";
		size_t size = 4 + 4 + 4; // header + manifest offset + file count (in manifest)
		uint manifestOffset = 4 + 4; /// location of manifest
		uint pos = 4 + 4; /// current location; needed for storing file offsets
		uint[] fileOffsets = cast(uint[])Mallocator.instance.allocate(uint.sizeof*files.length);
		scope(exit) Mallocator.instance.deallocate(fileOffsets);
		assert(fileOffsets.length == files.length);

		foreach(fi, f; files[])
		{
			size += 4 + 4 + 13; // ptr + length + name: manifest entry
			size += f.data.length; // payload
			manifestOffset += cast(uint)f.data.length; // payload only (the entry is IN the manifest)
			fileOffsets[fi] = pos;
			pos += cast(uint)f.data.length;
		}

		ubyte[] raw = cast(ubyte[])Mallocator.instance.allocate(size);
		scope(exit) Mallocator.instance.deallocate(raw);
		raw[0..4] = cast(ubyte[])header[];
		raw.write!(uint, EE)(manifestOffset, 4);
		size_t writePos = 4 + 4; // files start right after the header and offset
		foreach(f; files[])
		{
			raw[writePos..writePos+f.data.length] = f.data[];
			writePos += f.data.length;
		}
		assert(writePos == manifestOffset);
		raw.write!(uint, EE)(cast(uint)files.length, &writePos);
		foreach(fi, f; files[])
		{
			raw.write!(uint, EE)(fileOffsets[fi], &writePos);
			raw.write!(uint, EE)(cast(uint)f.data.length, &writePos);
			char[13] name = '\0';
			assert(f.name.length < 13); // f.name shouldn't include the null terminator (8+1+3 max)
			name[0..f.name.length] = f.name[];
			raw[writePos..writePos+13] = cast(ubyte[])name[];
			writePos += 13;
		}
		assert(writePos == raw.length);
		return raw.dup; /// FIXME: change the Savable API to allow for mallocated memory and @nogc
	}
	
	
	private this()
	{
		
	}
	
	~this()
	{

	}

	/++
	Header definitions for determining what type of archive is being loaded from a chunk of data
	+/
	enum char[4] headerDFGob = "GOB\x0a";
	enum char[4] headerJKGob = "GOB\x20";

	static ArcGob loadData(in ubyte[] data)
	{
		if(data[0..4]==headerDFGob) return loadDFGob(data);
		if(data[0..4]==headerJKGob) return loadJKGob(data);

		throw new Exception("Unknown header ("~cast(string)data[0..4]~")");
	}

	static ArcGob loadDFGob(in ubyte[] data)
	{
		import std.bitmanip, std.range;
		enum EE = Endian.littleEndian;
		size_t manifestPtr = cast(size_t) data[4..8].peek!(uint, EE);
		ArcGob ret = new ArcGob();
		
		const(ubyte)[] manifest = data[manifestPtr..$];
		if((manifest.length - 4) % (4+4+13) != 0) throw new Exception("File manifest has invalid length");
		uint numFiles = manifest.read!(uint, EE);
		if(manifest.length != numFiles*(4+4+13)) throw new Exception("File manifest length doesn't match number of files");
		foreach(fi; 0..numFiles)
		{
			ret.files.insert(new File(manifest[0..4+4+13], data));
			manifest = manifest.drop(4+4+13);
		}
		assert(manifest.length == 0);
		
		return ret;
	}
	
	static ArcGob loadJKGob(in ubyte[] data)
	{
		import std.bitmanip, std.range;
		enum EE = Endian.littleEndian;

		const(ubyte)[] header = data;
		header = header.drop(4);
		size_t unknownPtr = cast(size_t) header.read!(uint, EE);
		size_t manifestPtr = cast(size_t) header.read!(uint, EE);
		size_t numFiles = cast(size_t) header.read!(uint, EE);

		ArcGob ret = new ArcGob();

		const(ubyte)[] manifest = header[0..((128+4+4)*numFiles)];
		header = header.drop(manifest.length);
		foreach(fi; 0..numFiles)
		{
			size_t ptr = manifest.read!(uint, EE);
			size_t length = manifest.read!(uint, EE);
			const(ubyte)[] fileData = data[ptr..ptr+length];
			ret.addFile(cast(const(char[]))manifest[0..128], fileData );
			manifest = manifest.drop(128);
		}
		assert(manifest.length == 0);

		
		return ret;
	}
	
}




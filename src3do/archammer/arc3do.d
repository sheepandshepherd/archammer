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

module archammer.arc3do;

import archammer.util;
import pegged.grammar, pegged.peg;



/++
 + A 3do mesh.
 + 
 +/
class Arc3do : Savable
{
	@property const(SaveFormat[]) saveFormats() { return [  SaveFormat("3DO","3DO (Dark Forces)",cast(void[] delegate()) &data),
		SaveFormat("OBJ","OBJ", cast(void[] delegate()) &wavefrontObj )  ]; }
	
	/// Polygon shading type
	enum Shading : ubyte
	{
		flat = 0,
		gouraud = 1, /// shaded
		vertex = 2, /// drawn as points
		texture = 3,
		gourtex = 4, /// textured and shaded
		plane = 5 /// drawn like floor/ceiling; affected by INF and offsets
	}

	struct Tri
	{
		float[3][3] vertices; /// clockwise (left-handed)
		float[2][3] uvs = [[0,0],[0,0],[0,0]]; // avoid default NaNs
		ubyte[4] color = 0; /// [0..3] color rgb OR [3] palette index
		Shading shading = Shading.flat;

		/// returns: normal vector of the triangle
		/// TODO: normalize
		float[3] normal()
		{
			import std.algorithm.iteration, std.range;
			float[3] a = iota(0,3).map!(i => vertices[1][i]-vertices[2][i]).array;
			float[3] b = iota(0,3).map!(i => vertices[0][i]-vertices[1][i]).array;
			return [a[1]*b[2] - b[1]*a[2], a[2]*b[0] - b[2]*a[0], a[0]*b[1] - b[0]*a[1]];
		}
	}

	struct Quad
	{
		float[3][4] vertices; /// clockwise (left-handed)
		float[2][4] uvs = [[0,0],[0,0],[0,0],[0,0]]; // avoid default NaNs
		ubyte[4] color = 0; /// [0..3] color rgb OR [3] palette index
		Shading shading = Shading.flat;

		/// returns: normal vector of the given vertex $(PARAM v)
		/// TODO: normalize
		float[3] normal(size_t v)
		{
			import std.algorithm.iteration, std.range;
			float[3] a = iota(0,3).map!(i => vertices[v][i]-vertices[(v+1)%4][i]).array;
			float[3] b = iota(0,3).map!(i => vertices[(v+3)%4][i]-vertices[v][i]).array;
			return [a[1]*b[2] - b[1]*a[2], a[2]*b[0] - b[2]*a[0], a[0]*b[1] - b[0]*a[1]];
		}
	}

	struct Obj // can't use "Object"
	{
		string name = "obj";
		ptrdiff_t texture = -1; /// can be -1 for no texture
		// verts and uvs are stored poly-local while loaded, for simplicity
		Tri[] tris = [];
		Quad[] quads = [];

		/// for testing purposes; give every poly a random color
		void randomizeColors()
		{
			import std.random : uniform, Random, unpredictableSeed;
			auto gen = Random(unpredictableSeed);
			foreach(ref q; quads) foreach(i; 0..4) q.color[i] = cast(ubyte)uniform(0,256,gen);
			foreach(ref t; tris) foreach(i; 0..4) t.color[i] = cast(ubyte)uniform(0,256,gen);
		}
	}


	string name = "model";
	Obj[] objects = [];
	// palette is ignored
	string[] textures = [];



	/// comparison of vertices AND uvs rounded to 3 decimal places
	static pure bool sameVUV(float[5] a, float[5] b)
	{
		import std.math : lrint;
		foreach(i; 0..5)
		{
			if(lrint(a[i]*1000) != lrint(b[i]*1000)) return false;
		}
		return true;
	}
	/// comparison of vertices rounded to 3 decimal places
	static pure bool sameVertex(float[3] a, float[3] b)
	{
		import std.math : lrint;
		foreach(i; 0..3)
		{
			if(lrint(a[i]*1000) != lrint(b[i]*1000)) return false;
		}
		return true;
	}
	/// comparison of uvs rounded to 3 decimal places (KYL3DO has 3 places)
	static pure bool sameUV(float[2] a, float[2] b)
	{
		import std.math : lrint;
		foreach(i; 0..2)
		{
			if(lrint(a[i]*1000) != lrint(b[i]*1000)) return false;
		}
		return true;
	}

	/// DF's 3do format representation (plain ASCII text)
	string data()
	{
		import std.conv : text, to;
		import std.math : lrint;
		import std.algorithm.comparison : max;
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration : map;
		import std.array : join, Appender, appender; // for more efficient appending
		import std.range : only;
		import std.format : singleSpec, formatValue, format;
		import std.uni : toUpper; // uppercasing Shading enum
		import std.traits : EnumMembers; // iteration over Shading enum

		auto objText = appender!string();
		size_t vertNum = 0; // proper vertex count after indexification
		size_t polyNum = 0;

		// loop over OBJECTs
		foreach(o; objects) with(o)
		{
			// AFTER the header and vertices sections, but we'll generate it first.
			auto polyText = appender!string();
			auto uvText = appender!string();
			// indexed vertices for the vertices section
			float[5][] indexedVUVs = [];

			ptrdiff_t highestTexPoly = -1;
			ptrdiff_t highestTexVert = -1;

			/// generate poly texts; also index verts/uvs at the same time
			if(quads.length > 0)
			{
				polyText.put(text("QUADS ",quads.length,"\r\n"));
				uvText.put(text("TEXTURE QUADS ",quads.length,"\r\n"));
				foreach(size_t i, Quad q; quads)
				{
					bool textured = q.shading == Shading.texture || q.shading == Shading.gourtex;
					if(textured)
					{
						highestTexPoly = cast(ptrdiff_t)i;
					}
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..4)
					{
						ptrdiff_t iv = indexedVUVs.countUntil!(sameVUV)(to!(float[5])(q.vertices[j]~q.uvs[j]));
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVUVs.length;
							indexedVUVs ~= to!(float[5])(q.vertices[j]~q.uvs[j]);
						}
						if(textured) highestTexVert = max(highestTexVert,iv);
						
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iv));
					}
					polyText.put(text(" ",q.color[3]," ",q.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += quads.length;
			} /// end quads; mutually exclusive in DF engine.
			else if(tris.length > 0)
			{
				polyText.put(text("TRIANGLES ",tris.length,"\r\n"));
				uvText.put(text("TEXTURE TRIANGLES ",tris.length,"\r\n"));
				foreach(size_t i, Tri t; tris)
				{
					bool textured = t.shading == Shading.texture || t.shading == Shading.gourtex;
					if(textured)
					{
						highestTexPoly = cast(ptrdiff_t)i;
					}
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..3)
					{
						ptrdiff_t iv = indexedVUVs.countUntil!(sameVUV)(to!(float[5])(t.vertices[j]~t.uvs[j]));
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVUVs.length;
							indexedVUVs ~= to!(float[5])(t.vertices[j]~t.uvs[j]);
						}
						if(textured) highestTexVert = max(highestTexVert,iv);
						
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iv));
					}
					polyText.put(text(" ",t.color[3]," ",t.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += tris.length;
			}

			/// generate header and vert/uv texts, and add the poly texts
			objText.put(text("OBJECT \"",o.name,"\"\r\nTEXTURE ",o.texture,
				"\r\nVERTICES ",indexedVUVs.length,"\r\n"));
			foreach(size_t i, float[5] v; indexedVUVs)
			{
				int[] arr1 = [ 1, 2, 3, 4 ];
				int[] arr2 = [ 5, 6 ];
				auto squares = map!(a => a * a)(arr1);

				objText.put(text(" ",i,": ",v[0..3].map!(a => format("%.3f",a)).join(" "),"\r\n"));
			}
			objText.put(polyText.data);
			if(highestTexPoly >= 0 && highestTexVert >= 0)
			{
				objText.put(text("TEXTURE VERTICES ",indexedVUVs.length,"\r\n"));
				foreach(size_t i, float[5] u; indexedVUVs)
				{
					objText.put(text(" ",i,": ",u[3..5].map!(a => format("%.3f",a)).join(" "),"\r\n"));
				}
				objText.put(uvText.data);
			}

			/// increment total vert count for the whole 3do
			vertNum += indexedVUVs.length;

			objText.put("\r\n");
		}

		// header
		auto ret = appender!string(text("3DO 1.30\r\n3DONAME ",name,"\r\nOBJECTS ",
			objects.length,"\r\nVERTICES ",vertNum,"\r\nPOLYGONS ",polyNum,
			"\r\nPALETTE METAL.PAL\r\n\r\nTEXTURES ",textures.length,"\r\n"));

		foreach(t; textures)
		{
			ret.put(text(" TEXTURE: ",t,"\r\n"));
		}
		ret.put("\r\n");

		ret.put(objText.data);

		return ret.data;
	} // end data()

	/// wavefront OBJ format representation (plain text)
	string wavefrontObj()
	{
		import std.conv : text;
		import std.math : lrint;
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration;
		import std.array : join, Appender, appender; // for more efficient appending
		import std.range : iota, only, array, retro;
		import std.format : singleSpec, formatValue, format;
		import std.uni : toUpper; // uppercasing Shading enum
		import std.traits : EnumMembers; // iteration over Shading enum
		import std.datetime;
		
		auto objText = appender!string();
		/// Wavefront OBJ indices (vert, uv, normal) are *global* and start at 1
		size_t vNum = 1;
		size_t uNum = 1;
		size_t nNum = 1;
		
		objText.put("# ArcHammer 3DO->OBJ export\n");
		
		// loop over OBJECTs
		foreach(o; objects) with(o)
		{
			/// TODO: check name for uniqueness?
			auto polyText = appender!string("o "~name~"\n");

			/// generate poly texts
			if(quads.length > 0)
			{
				// add verts
				polyText.put(quads.map!(q => q.vertices[].dup) // float[3][4][]
					.join // float[3][]
					.map!(v => "v "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\n");
				// add uvs
				polyText.put(quads.map!(q => q.uvs[].dup) // float[2][4][]
					.join // float[2][]
					.map!(v => "vt "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\n");
				// add normals
				polyText.put(quads.map!( q => iota(0,4).map!(qi => q.normal(qi)) ) // float[3][4][]
					.join // float[3][]
					.map!(v => "vn "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\nusemtl None\ns off\n");

				foreach(qi; 0..quads.length)
				{
					polyText.put("f");
					foreach(vi; iota(0,4,1).retro)
					{
						polyText.put(" ");
						polyText.put(only(qi*4+vi+vNum,qi*4+vi+uNum,qi*4+vi+nNum).map!(a => a.text).join("/").array);
					}
					polyText.put("\n");
				}
				vNum += 4*quads.length;
				uNum += 4*quads.length;
				nNum += 4*quads.length;
			} /// end quads; mutually exclusive in DF engine.
			else if(tris.length > 0)
			{
				// add verts
				polyText.put(tris.map!(t => t.vertices[].dup) // float[3][4][]
					.join // float[3][]
					.map!(v => "v "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\n");
				// add uvs
				polyText.put(
					tris.map!(t => t.uvs[].dup) // float[2][4][]
					.join // float[2][]
					.map!(v => "vt "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\n");
				// add normals
				polyText.put(
					tris.map!( t => t.normal() ) // float[3][]
					.map!(v => "vn "~(v[].map!(vi => text(vi)).join(" "))) // string[]
					.join("\n").array); // string
				polyText.put("\ns off\n");

				foreach(ti; 0..tris.length)
				{
					polyText.put("f");
					foreach(vi; iota(0,3,1).retro)
					{
						polyText.put(" "); ///only(ti*4+vi+vNum,ti*4+vi+uNum,ti+nNum)
						polyText.put(only(ti*3+vi+vNum,ti*3+vi+uNum,ti+nNum).map!(a => a.text).join("/").array);
					}
					polyText.put("\n");
				}
				vNum += 3*tris.length;
				uNum += 3*tris.length;
				nNum += tris.length;
			}
			objText.put(polyText.data);
			objText.put("\n");
		}
		
		return objText.data;
	} // end wavefrontObj()

	/// WIP
	version(none) string collada()
	{
		import std.conv : text;
		import std.math : lrint;
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration : map;
		import std.array : join, Appender, appender; // for more efficient appending
		import std.range : only;
		import std.format : singleSpec, formatValue, format;
		import std.uni : toUpper; // uppercasing Shading enum
		import std.traits : EnumMembers; // iteration over Shading enum
		import std.datetime;
		
		auto objText = appender!string();
		auto sceneText = appender!string();
		size_t vertNum = 0; // proper vertex count after indexification
		size_t polyNum = 0;

		/// export time
		/// we're at `now` now
		string now = Clock.currTime.toISOExtString();

		objText.put(`<?xml version="1.0" encoding="utf-8"?>
<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
  <asset>
    <contributor>
      <author>DF Modder</author>
      <authoring_tool>ArcHammer</authoring_tool>
    </contributor>
    <created>`~now~`</created>
    <modified>`~now~`</modified>
    <unit name="meter" meter="1"/>
    <up_axis>Z_UP</up_axis>
  </asset>
  <library_cameras/>
  <library_lights/>
  <library_images/>
  <library_effects/>
  <library_materials/>
  <library_geometries>`);

		sceneText.put("  <library_visual_scenes>\n");

		// loop over OBJECTs
		foreach(o; objects) with(o)
		{
			// AFTER the header and vertices sections, but we'll generate it first.
			auto polyText = appender!string();
			auto uvText = appender!string();

			polyText.put(`
    <geometry id="Cube-mesh" name="Cube">
      <mesh>`);

			// indexed vertices for the vertices section
			float[3][] indexedVerts = [];
			float[2][] indexedUVs = [];
			/// generate poly texts; also index verts/uvs at the same time
			if(quads.length > 0)
			{
				polyText.put(text("QUADS ",quads.length,"\r\n"));
				uvText.put(text("TEXTURE QUADS ",quads.length,"\r\n"));
				foreach(size_t i, Quad q; quads)
				{
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..4)
					{
						ptrdiff_t iv = indexedVerts.countUntil!(sameVertex)(q.vertices[j]);
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVerts.length;
							indexedVerts ~= (q.vertices[j]);
						}
						ptrdiff_t iu = indexedUVs.countUntil!(sameUV)(q.uvs[j]);
						if(iu == -1)
						{
							iu = cast(ptrdiff_t)indexedUVs.length;
							indexedUVs ~= (q.uvs[j]);
						}
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iu));
					}
					polyText.put(text(" ",q.color[3]," ",q.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += quads.length;
			} /// end quads; mutually exclusive in DF engine.
			else if(tris.length > 0)
			{
				polyText.put(text("TRIANGLES ",tris.length,"\r\n"));
				uvText.put(text("TEXTURE TRIANGLES ",tris.length,"\r\n"));
				foreach(size_t i, Tri t; tris)
				{
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..3)
					{
						ptrdiff_t iv = indexedVerts.countUntil!(sameVertex)(t.vertices[j]);
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVerts.length;
							indexedVerts ~= (t.vertices[j]);
						}
						ptrdiff_t iu = indexedUVs.countUntil!(sameUV)(t.uvs[j]);
						if(iu == -1)
						{
							iu = cast(ptrdiff_t)indexedUVs.length;
							indexedUVs ~= (t.uvs[j]);
						}
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iu));
					}
					polyText.put(text(" ",t.color[3]," ",t.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += tris.length;
			}
			
			/// generate header and vert/uv texts, and add the poly texts
			objText.put(text("OBJECT \"",o.name,"\"\r\nTEXTURE ",o.texture,
					"\r\nVERTICES ",indexedVerts.length,"\r\n"));
			foreach(size_t i, float[3] v; indexedVerts)
			{
				//import std.range;
				
				int[] arr1 = [ 1, 2, 3, 4 ];
				int[] arr2 = [ 5, 6 ];
				auto squares = map!(a => a * a)(arr1);
				
				objText.put(text(" ",i,": ",v[].map!(a => format("%.3f",a)).join(" "),"\r\n"));
			}
			objText.put(polyText.data);
			objText.put(text("TEXTURE VERTICES ",indexedUVs.length,"\r\n"));
			foreach(size_t i, float[2] u; indexedUVs)
			{
				objText.put(text(" ",i,": ",u[].map!(a => format("%.3f",a)).join(" "),"\r\n"));
			}
			objText.put(uvText.data);
			
			/// increment total vert count for the whole 3do
			vertNum += indexedVerts.length;
			
			objText.put("\r\n");
		}
		
		// header
		auto ret = appender!string(text("3DO 1.30\r\n3DONAME ",name,"\r\nOBJECTS ",
				objects.length,"\r\nVERTICES ",vertNum,"\r\nPOLYGONS ",polyNum,
				"\r\nPALETTE METAL.PAL\r\n\r\nTEXTURES ",textures.length,"\r\n"));
		
		foreach(t; textures)
		{
			ret.put(text(" TEXTURE: ",t,"\r\n"));
		}
		ret.put("\r\n");
		
		ret.put(objText.data);
		
		return ret.data;
	} // end collada()

	/// WIP. TODO: get ASSIMP export working. Low priority
	version(none) void saveMesh(string filePath)
	{
		import std.conv : text;
		import std.algorithm.searching : countUntil;
		import std.algorithm.iteration : map;
		import std.array : join, Appender, appender; // for more efficient appending
		import std.range : only;
		import std.format : singleSpec, formatValue, format;
		import std.uni : toUpper; // uppercasing Shading enum
		import std.traits : EnumMembers; // iteration over Shading enum
		import std.stdio : writeln;
		import std.file;
		import std.path;
		import std.algorithm.searching : findSplitBefore;
		import std.string : toStringz, fromStringz;
		import derelict.assimp3.assimp;
		
		/// scene (== 3DO)
		/+uint mNumMeshes;
	    aiMesh** mMeshes;
	    uint mNumMaterials;
	    aiMaterial** mMaterials;
	    uint mNumTextures;
	    aiTexture** mTexture;+/
		
		/// submesh (== OBJECT)
		/+uint mPrimitiveTypes;
		uint mNumVertices;
		uint mNumFaces;
		aiVector3D* mVertices;
		aiVector3D* mNormals;
		aiColor4D*[AI_MAX_NUMBER_OF_COLOR_SETS] mColors;
		aiVector3D*[AI_MAX_NUMBER_OF_TEXTURECOORDS] mTextureCoords;
		uint[AI_MAX_NUMBER_OF_TEXTURECOORDS] mNumUVComponents;
		aiFace* mFaces;
		uint mMaterialIndex;
		aiString mName;+/
		
		aiScene mesh;
		auto rootNode = aiNode();
		mesh.mRootNode = &rootNode;
		auto meshes = new aiMesh*[objects.length];
		mesh.mNumMeshes = objects.length;
		mesh.mMeshes = meshes.ptr;

		size_t vertNum = 0; // proper vertex count after indexification
		size_t polyNum = 0;
		
		// loop over OBJECTs
		foreach(oi, o; objects) with(o)
		{
			auto m = new aiMesh();
			meshes[oi] = &m;
			m.mName.length = name.length;
			m.mName.data[0..name.length] = name[];

			// indexed vertices for the vertices section
			float[3][] indexedVerts = [];
			float[2][] indexedUVs = [];
			/// generate poly data; also index verts/uvs at the same time
			if(quads.length > 0)
			{
				m.mNumFaces = quads.length;
				foreach(size_t i, Quad q; quads)
				{
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..4)
					{
						ptrdiff_t iv = indexedVerts.countUntil!(sameVertex)(q.vertices[j]);
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVerts.length;
							indexedVerts ~= (q.vertices[j]);
						}
						ptrdiff_t iu = indexedUVs.countUntil!(sameUV)(q.uvs[j]);
						if(iu == -1)
						{
							iu = cast(ptrdiff_t)indexedUVs.length;
							indexedUVs ~= (q.uvs[j]);
						}
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iu));
					}
					polyText.put(text(" ",q.color[3]," ",q.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += quads.length;
			} /// end quads; mutually exclusive in DF engine.
			else if(tris.length > 0)
			{
				m.mNumFaces = tris.length;
				foreach(size_t i, Tri t; tris)
				{
					polyText.put(text(" ",i,":"));
					uvText.put(text(" ",i,":"));
					foreach(j; 0..3)
					{
						ptrdiff_t iv = indexedVerts.countUntil!(sameVertex)(t.vertices[j]);
						if(iv == -1)
						{
							iv = cast(ptrdiff_t)indexedVerts.length;
							indexedVerts ~= (t.vertices[j]);
						}
						ptrdiff_t iu = indexedUVs.countUntil!(sameUV)(t.uvs[j]);
						if(iu == -1)
						{
							iu = cast(ptrdiff_t)indexedUVs.length;
							indexedUVs ~= (t.uvs[j]);
						}
						polyText.put(text(" ",iv));
						uvText.put(text(" ",iu));
					}
					polyText.put(text(" ",t.color[3]," ",t.shading.text.toUpper,"\r\n"));
					uvText.put("\r\n");
				}
				polyNum += tris.length;
			}
			
			/// generate header and vert/uv texts, and add the poly texts
			objText.put(text("OBJECT \"",o.name,"\"\r\nTEXTURE ",o.texture,
					"\r\nVERTICES ",indexedVerts.length,"\r\n"));
			foreach(size_t i, float[3] v; indexedVerts)
			{
				//import std.range;
				
				int[] arr1 = [ 1, 2, 3, 4 ];
				int[] arr2 = [ 5, 6 ];
				auto squares = map!(a => a * a)(arr1);
				
				objText.put(text(" ",i,": ",v[].map!(a => format("%.3f",a)).join(" "),"\r\n"));
			}
			objText.put(polyText.data);
			objText.put(text("TEXTURE VERTICES ",indexedUVs.length,"\r\n"));
			foreach(size_t i, float[2] u; indexedUVs)
			{
				objText.put(text(" ",i,": ",u[].map!(a => format("%.3f",a)).join(" "),"\r\n"));
			}
			objText.put(uvText.data);
			
			/// increment total vert count for the whole 3do
			vertNum += indexedVerts.length;
			
			objText.put("\r\n");
		}
		
		// header
		auto ret = appender!string(text("3DO 1.30\r\n3DONAME ",name,"\r\nOBJECTS ",
				objects.length,"\r\nVERTICES ",vertNum,"\r\nPOLYGONS ",polyNum,
				"\r\nPALETTE METAL.PAL\r\n\r\nTEXTURES ",textures.length,"\r\n"));
		
		foreach(t; textures)
		{
			ret.put(text(" TEXTURE: ",t,"\r\n"));
		}
		ret.put("\r\n");
		
		ret.put(objText.data);
		
		return ret.data;
	} // end saveMesh()

	static Arc3do loadMesh(string filePath)
	{
		import std.file, std.path;
		if(!exists(filePath)) throw new Exception(filePath~" does not exist.");
		ubyte[] data = cast(ubyte[])read(filePath);
		return loadMeshData(data, filePath.baseName);
	}

	/// load a mesh with ASSIMP.
	/// Returns: the loaded Arc3do.
	static Arc3do loadMeshData(in ubyte[] data, in string fileBaseName)
	{
		import std.file;
		import std.path;
		import std.algorithm.searching : findSplitBefore;
		import std.string : toStringz, fromStringz;
		import std.conv : text;
		import derelict.assimp3.assimp;

		string extHint = extension(fileBaseName);
		string name = fileBaseName.findSplitBefore(".")[0];

		const(aiScene*) mesh = aiImportFileFromMemory( /++cast(const(void)*)+/data.ptr, cast(uint)data.length, 
			aiProcess_CalcTangentSpace | aiProcess_Triangulate | aiProcess_JoinIdenticalVertices | 
			aiProcess_SortByPType | aiProcess_FlipWindingOrder ,  extHint.toStringz );

		if(!mesh)
		{
			throw new Exception(aiGetErrorString().fromStringz.text);
		}
		scope(exit)
		{
			aiReleaseImport(mesh);
		}

		/// scene (== 3DO)
		/+uint mNumMeshes;
	    aiMesh** mMeshes;
	    uint mNumMaterials;
	    aiMaterial** mMaterials;
	    uint mNumTextures;
	    aiTexture** mTexture;+/

		/// submesh (== OBJECT)
		/+uint mPrimitiveTypes;
		uint mNumVertices;
		uint mNumFaces;
		aiVector3D* mVertices;
		aiVector3D* mNormals;
		aiColor4D*[AI_MAX_NUMBER_OF_COLOR_SETS] mColors;
		aiVector3D*[AI_MAX_NUMBER_OF_TEXTURECOORDS] mTextureCoords;
		uint[AI_MAX_NUMBER_OF_TEXTURECOORDS] mNumUVComponents;
		aiFace* mFaces;
		uint mMaterialIndex;
		aiString mName;+/

		Arc3do ret = new Arc3do();
		ret.name = name;

		ret.objects.reserve(cast(size_t)mesh.mNumMeshes);
		
		foreach(mi; 0..cast(size_t)mesh.mNumMeshes)
		{
			const(aiMesh*) m = mesh.mMeshes[mi];
			Obj o;
			o.name = m.mName.data[0..cast(size_t)m.mName.length].idup;
			if(o.name is null || o.name.length == 0 || o.name[0] == '\0')
			{
				import std.conv;
				o.name = text("obj",mi);
			}
			size_t mati = cast(size_t)m.mMaterialIndex;
			const(aiMaterial*) mat = (mati < mesh.mNumMaterials)?(mesh.mMaterials[mati]):null;
			foreach(pi; 0..cast(size_t)m.mNumFaces)
			{
				const(aiFace) f = m.mFaces[pi];
				float[3] colorPart = 0f;
				if(f.mNumIndices == 4)
				{
					Quad q;
					foreach(vi; 0..4)
					{
						const(aiVector3D) av = m.mVertices[f.mIndices[vi]];
						float[3] v = [av.x, av.y, av.z];
						q.vertices[vi] = v;
						if(m.mTextureCoords[0] !is null)
						{
							const(aiVector3D) au = (m.mTextureCoords[0])[f.mIndices[vi]];
							float[2] u = [au.x, au.y];
							q.uvs[vi] = u;
						}
						if(m.mColors[0] !is null)
						{
							const(aiColor4D) ac = (m.mColors[0])[f.mIndices[vi]];
							colorPart[0] += ac.r;
							colorPart[1] += ac.g;
							colorPart[2] += ac.b;
						}
						else foreach(ci; 0..3) colorPart[ci] += 1f; // default
					}
					foreach(ci; 0..3) q.color[ci] = cast(ubyte)((255f/4f)*colorPart[ci]);
					q.shading = Shading.gourtex;
					o.quads ~= q;
				}
				else if(f.mNumIndices == 3)
				{
					Tri t;
					foreach(vi; 0..3)
					{
						const(aiVector3D) av = m.mVertices[f.mIndices[vi]];
						float[3] v = [av.x, av.y, av.z];
						t.vertices[vi] = v;
						if(m.mTextureCoords[0] !is null)
						{
							const(aiVector3D) au = (m.mTextureCoords[0])[f.mIndices[vi]];
							float[2] u = [au.x, au.y];
							t.uvs[vi] = u;
						}
						if(m.mColors[0] !is null)
						{
							const(aiColor4D) ac = (m.mColors[0])[f.mIndices[vi]];
							colorPart[0] += ac.r;
							colorPart[1] += ac.g;
							colorPart[2] += ac.b;
						}
						else foreach(ci; 0..3) colorPart[ci] += 1f; // default
					}
					foreach(ci; 0..3) t.color[ci] = cast(ubyte)((255f/3f)*colorPart[ci]);
					t.shading = Shading.gourtex;
					o.tris ~= t;
				}
			} // end foreach face
			ret.objects ~= o;
		} // end foreach submesh
		return ret;
	}

	/// load a DF 3do using the PEG grammar.
	/// Returns: the loaded Arc3do.
	static Arc3do load3do(string filePath)
	{
		import std.file;
		
		string content = readText(filePath);
		return load3doText(content);
	}

	/// load a DF 3do using the PEG grammar.
	/// Returns: the parsed Arc3do.
	static Arc3do load3doText(string content)
	{
		import std.conv : to;
		import std.algorithm.searching;
		import std.algorithm.iteration;
		import std.uni : icmp;
		import std.range : array;

		/// TODO: don't rely on the "count" lines, and don't throw exceptions if they're wrong. just ignore them

		ParseTree tree;
		tree = Grammar.Def(preprocessLineComments(content));
		
		if(!tree.successful)
		{
			string treeString;
			treeString = tree.toString();
			throw new Exception("3DO PEG parse tree failed.\n\n"~treeString);
		}

		auto ret = new Arc3do();
		// get data from the parse tree
		auto headerAnd = tree.ch(0,0,0); // : and! directly below Header
		ret.name = headerAnd.ch(1).matches[0]; // HeaderName
		
		ptrdiff_t texHeaderID = headerAnd.children[2..7] // the 5 HeaderPart entries
			.countUntil!((a,b) => icmp(a.ch(0,0).name,b)==0)("Grammar.TexHeader");
		if(texHeaderID < 0) throw new Exception("Header doesn't contain a TEXTURES entry.");
		ParseTree texHeader = headerAnd.children[2+texHeaderID].ch(0,0,0); // HeaderPart => or! => TexHeader => and!
		int texNum = to!int(texHeader.matches[0]);
		if(texHeader.ch(1).children.length != texNum) throw new Exception("TEXTURES count doesn't match");
		///ret.textures.reserve(texNum); // allocate without changing slice length
		if(texNum > 0) ret.textures = texHeader.ch(1).matches; //.each!(c => ret.textures ~= c.matches[0]);

		// loop over objects
		// o = the and! node below each ObjDef. note the use of map to aggregate the or! children.
		auto objDefs = tree.ch(0,1).children.map!(od => od.ch(0));
		foreach(o; objDefs) // ObjDef => and!
		{
			assert(o != ParseTree());
			Obj obj;
			obj.name = o.matches[0];
			obj.texture = o.ch(1).matches[0].to!(ptrdiff_t);
			
			float[3][] verts = []; /// temp storage for vertices
			size_t vertCount = o.ch(2).matches[0].to!(size_t);
			verts.reserve(vertCount);
			if(o.ch(2,0,1).children.length != vertCount) throw new Exception("VERTICES count doesn't match");
			foreach(v; o.ch(2,0,1).children) // v : VertDef
			{
				float[3] vv;			// c : and!
				vv[] = v.ch(0).children.map!(c => c.matches[0].to!float).array;
				verts ~= vv;
			}
			/// Quads or Tris?
			auto qtsDef = o.ch(3,0,0); // QTsDef => or! => (QuadDef / TriDef)
			
			/// inner function: process the parse tree of a polygon
			void processPoly(T)(ParseTree p) if(is(T : Quad) || is(T : Tri))
			{
				enum size_t N = is(T : Quad)?4:3;
				T[] arr;
				size_t num = p.matches[0].to!size_t;
				arr.reserve(num);
				auto polyDefs = p.ch(0,1).children;
				if(num != polyDefs.length) throw new Exception("Poly count doesn't match.");
				foreach(polyDef; polyDefs)
				{
					import std.string : toLower;
					T poly;
					poly.vertices[] = polyDef.matches[0..N].map!(i => verts[i.to!size_t]).array;
					poly.color[3] = polyDef.matches[N].to!ubyte;
					// magic: string directly to enum by name.
					poly.shading = polyDef.matches[N+1].toLower.to!Shading;
					arr ~= poly;
				}
				static if(is(T : Quad)) obj.quads = arr;
				else obj.tris = arr;
			}
			
			
			if(icmp(qtsDef.name,"Grammar.QuadsDef")==0)
			{
				processPoly!Quad(qtsDef);
			}
			else if(icmp(qtsDef.name,"Grammar.TrisDef")==0)
			{
				processPoly!Tri(qtsDef);
			}

			/// UVs and UVPolys
			auto uvsDef = o.ch(4,0,0); // option! => UVsDef? => and!
			if(uvsDef != ParseTree()) // null tree = no UVs defined
			{
				float[2][] uvs;
				size_t uvCount = uvsDef.matches[0].to!(size_t);
				uvs.reserve(uvCount);
				if(uvsDef.ch(1).children.length != vertCount) throw new Exception("VERTICES count doesn't match");
				foreach(u; uvsDef.ch(1).children) // u : UVDef
				{
					float[2] uu;			// c : and!
					uu[] = u.ch(0).children.map!(c => c.matches[0].to!float).array;
					uvs ~= uu;
				}

				auto uvqtsDef = o.ch(5,0,0,0); // option! => UVQTsDef? => or! => (UVTrisDef / UVQuadsDef)
				void processUVPoly(T)(ParseTree p) if(is(T : Quad) || is(T : Tri))
				{
					import std.algorithm.comparison : min;
					enum size_t N = is(T : Quad)?4:3;
					T[] arr;
					static if(is(T : Quad)) arr = obj.quads;
					else arr = obj.tris;
					size_t num = p.matches[0].to!size_t;
					//					and! => zeroOrMore!
					auto uvPolyDefs = p.ch(0,1).children; // [UVTriDef / UVQuadDef]
					if(num != uvPolyDefs.length) throw new Exception("UVPoly count doesn't match.");
					if(num > arr.length) throw new Exception("More UVPolys than Polys defined.");
					foreach(i; 0..min(arr.length,uvPolyDefs.length))
					{
						arr[i].uvs[] = uvPolyDefs[i].matches[0..N].map!(i => uvs[i.to!size_t]).array;
					}
				}
				if(icmp(uvqtsDef.name,"Grammar.UVQuadsDef")==0)
				{
					processUVPoly!Quad(uvqtsDef);
				}
				else if(icmp(uvqtsDef.name,"Grammar.UVTrisDef")==0)
				{
					processUVPoly!Tri(uvqtsDef);
				}
			}

			ret.objects ~= obj;
		}

		return ret;
	}
	
	
	
	/// 3do PEG grammar
	/// most (all?) DF 3DOs end with \x1A SUB. accounted for by <.?>, but could narrow it down? Might ignore to support true plain-text 3DOs
	mixin(grammar(`
Grammar:

Float		<~ Int ('.' digits )?
Int			<~ Sign? digits
Sign		<; '-' / '+'

# some vanilla DF 3DOs have OBJECT names with missing doublequotes. it seems they're optional.
String		<~ :doublequote? Text :doublequote?
# make sure Char does NOT match whitespace
NonChar		<: (doublequote / quote / blank)
Char		<~ (!NonChar .)
Text		<~ (Char / space)+
EndLine		<: space* ((eol+ space*) / (eol* eoi))
End			<: EndLine+

# HEADER SECTION -------------------------------------------------------------------
HeaderText	<- :"3DO" :space+ Float End
HeaderName	<- :"3DONAME" :space+ ~(Char+) End
ObjNum		<- :"OBJECTS" :space+ digits End
VertNum		<- :"VERTICES" :space+ digits End
PolyNum		<- :"POLYGONS" :space+ digits End
Palette		<- :"PALETTE" :space+ ~(Char+) End
TexNum		<- :"TEXTURES" :space+ digits End
TexDef		<- :"TEXTURE:" :space* ~(Char+) End
TexHeader	<- TexNum TexDef*
HeaderPart	<- ObjNum / VertNum / PolyNum / Palette / TexHeader

Header		<- HeaderText HeaderName HeaderPart HeaderPart HeaderPart HeaderPart HeaderPart

# OBJECT SECTION -------------------------------------------------------------------
ObjHeader	<- :"OBJECT" :space+ String End
ObjTexture	<- :"TEXTURE" :space+ Int End
VertDef		<- :digits :":" :space* Float :space+ Float :space+ Float End
UVDef		<- :digits :":" :space* Float :space+ Float End
QuadNum		<- :"QUADS" :space+ digits End
TriNum		<- :"TRIANGLES" :space+ digits End
QuadPart	<- :digits :":" :space* digits :space+ digits :space+ digits :space+ digits
TriPart		<- :digits :":" :space* digits :space+ digits :space+ digits
QuadDef		<- QuadPart :space+ digits :space+ ~(Char+) End
TriDef		<- TriPart :space+ digits :space+ ~(Char+) End
UVQuadDef	<- QuadPart End
UVTriDef	<- TriPart End
UVNum		<- :"TEXTURE" :space+ VertNum
UVQuadNum	<- :"TEXTURE" :space+ QuadNum
UVTriNum	<- :"TEXTURE" :space+ TriNum

# Verts are required. Presumably at least one of Quads/Tris is required.
VertsDef	<- VertNum VertDef+
QuadsDef	<- QuadNum QuadDef*
TrisDef		<- TriNum TriDef*
QTsDef		<- QuadsDef / TrisDef

# UVs are optional
UVsDef		<- UVNum UVDef*
UVQuadsDef	<- UVQuadNum UVQuadDef*
UVTrisDef	<- UVTriNum UVTriDef*
UVQTsDef	<- UVQuadsDef / UVTrisDef

ObjDef		<- ObjHeader ObjTexture VertsDef QTsDef UVsDef? UVQTsDef?


Def	<- Header ObjDef+ :.? eoi
`));


}
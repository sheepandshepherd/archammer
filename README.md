Arc Hammer
==========
Arc Hammer is a converter tool for Dark Forces file formats.

The main executable has ~~a command-line interface and~~ a GUI for converting DF files to/from more common formats.

Additionally, the libraries for each file format can be used as dependencies in other projects. They can be included statically in D projects, ~~or built as dynamic libraries with a C interface for use with other programming languages~~.

Supported file formats
----------------------
DF format   | Import formats | Export formats  
------------|----------------|----------------  
3DO Mesh    | [See ASSIMP list](http://assimp.sourceforge.net/main_features_formats.html) | Wavefront OBJ  
PAL Palette | -              | Gimp GPL  
BM Texture  | -              | PPM P6  
GOB Archive | -              | -  

Compiling
---------
1. Install DMD (or another D compiler), DUB, and GTK+ binaries (see [here](http://gtkd.org/download.html) for a Windows installer).
2. Install ASSIMP (on Windows, put the DLLs in the archammer/bin/ folder where Arc Hammer will be built).
3. Open a terminal/command prompt in the archammer/ folder (containing dub.json) and type `dub` or `dub --build=release`. DUB will download the dependencies and build the executable.

Licenses
--------
Arc Hammer GUI: GPL v2.0 or later - <http://www.gnu.org/licenses/old-licenses/gpl-2.0.html>  
Arc Hammer submodule libraries: MIT License - <https://opensource.org/licenses/MIT>  

Tools and libraries used
------------------------
D Compiler: DMD >= v2.070.0 - <http://dlang.org/download.html#dmd>  
D Package Manager: DUB - <http://code.dlang.org/download>  
GUI Library: GTK+ (GtkD wrapper) - <http://gtkd.org/>  
Derelict bindings [Util, GL3, FI] - <https://github.com/DerelictOrg>  
PEG generator: Pegged - <https://github.com/PhilippeSigaud/Pegged>  

Links
-----
GitHub repository - <https://github.com/sheepandshepherd/archammer>  
~~DF-21 forum topic - <>~~  

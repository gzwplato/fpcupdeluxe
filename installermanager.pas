unit installerManager;
{ Installer state machine
Copyright (C) 2012-2014 Ludo Brands, Reinier Olislagers

This library is free software; you can redistribute it and/or modify it
under the terms of the GNU Library General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at your
option) any later version with the following modification:

As a special exception, the copyright holders of this library give you
permission to link this library with independent modules to produce an
executable, regardless of the license terms of these independent modules,and
to copy and distribute the resulting executable under terms of your choice,
provided that you also meet, for each linked independent module, the terms
and conditions of the license of that module. An independent module is a
module which is not derived from or based on this library. If you modify
this library, you may extend this exception to your version of the library,
but you are not obligated to do so. If you do not wish to do so, delete this
exception statement from your version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
for more details.

You should have received a copy of the GNU Library General Public License
along with this library; if not, write to the Free Software Foundation,
Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
}

{$mode objfpc}{$H+}
{Define NOCONSOLE e.g. if using Windows GUI {$APPTYPE GUI} or -WG
this will disable writeln calls
}
{not $DEFINE NOCONSOLE}

interface

uses
  Classes, SysUtils,installerCore,installerFpc,
  {$ifndef FPCONLY}
  installerLazarus,
  {$endif}
  installerHelp, installerUniversal, fpcuputil, FileUtil, LazFileUtils
  {$ifdef UNIX}
  ,dynlibs,Unix
  {$endif UNIX}
  ;

// Get revision from our source code repository:
// If you have a file not found error for revision.inc, please make sure you compile hgversion.pas before compiling this project.
{$i revision.inc}
//Contains RevisionStr and versiondate constants

// These sequences determine standard installation/uninstallation order/content:
// Note that a single os/cpu/sequence combination will only be executed once (the state machine checks for this)
Const
  Sequences=
    //default sequence. Using declare makes this show up in the module list given by fpcup --help
    // If you don't want that, use DeclareHidden
    'Declare default;'+ //keyword Declare gives a name to a sequence of commands
    {$ifndef FPCONLY}
    // CheckDevLibs has stubs for anything except Linux, where it does check development library presence
    'Exec CheckDevLibs;'+ //keyword Exec executes a function/procedure; must be defined in TSequencer.DoExec
    {$endif}
    'Do fpc;'+ //keyword Do means run the specified declared sequence
    {$ifndef FPCONLY}
    // Lazbuild: make sure we can at least compile LCL programs
    'Do lazbuild;'+
    'Do helplazarus;'+
    //'Do DOCEDITOR;'+
    //Get default external packages/universal modules
    'Do UniversalDefault;'+
    //Recompile user IDE so any packages selected by the
    //universal installer are compiled into the IDE:
    'Do USERIDE;'+
    //Any cross compilation; must be at end because it resets state machine run memory
    'Do LCLCross;'+
    {$endif}
    'End;'+ //keyword End specifies the end of the sequence

//default sequence for win32
    'Declare defaultwin32;'+
    {$ifndef FPCONLY}
    'Exec CheckDevLibs;'+ //keyword Exec executes a function/procedure; must be defined in TSequencer.DoExec
    {$endif}
    'Do fpc;'+
    {$ifndef FPCONLY}
    // Lazbuild: make sure we can at least compile LCL programs
    'Do lazbuild;'+
    'Do helplazarus;'+
    //'Do DOCEDITOR;'+
    // Get default external packages/universal modules
    'Do UniversalDefault;'+
    // Recompile user IDE so any packages selected by the
    // universal installer are compiled into the IDE:
    'Do USERIDE;'+
    {$endif}
    {$ifdef mswindows} //not really necessary as crosswin checks arechitecture anyway
    'Do crosswin32-64;'+  //this has to be the last. All TExecState reset!
    {$endif}
    {$ifndef FPCONLY}
    // Any further cross compilation; must be at end because it resets state machine run memory
    'Do LCLCross;'+
    {$endif}
    'End;'+

//cross sequence for win32. Note: if changing this name,
    //also change checks for this in skipmodules etc.
    'Declare crosswin32-64;'+
    'Do FPCCrossWin32-64;'+
    {$ifndef FPCONLY}
    'Do LazarusCrossWin32-64;'+
    {$endif}
    'End;'+

//default sequence for win64
{todo: win64 sequence currently not enabled; see
$elseif defined(win64)
below}
    'Declare defaultwin64;'+
    {$ifndef FPCONLY}
    // CheckDevLibs has stubs for anything except Linux, where it does check development library presence
    'Exec CheckDevLibs;'+
    {$endif}
    'Do fpc;'+
    {$ifndef FPCONLY}
    // Lazbuild: make sure we can at least compile LCL programs
    'Do lazbuild;'+
    'Do helplazarus;'+
    //'Do DOCEDITOR;'+
    //Get default external packages/universal modules
    'Do UniversalDefault;'+
    //Recompile user IDE so any packages selected by the
    //universal installer are compiled into the IDE:
    'Do USERIDE;'+
    {$endif}
    'Do crosswin64-32;'+  //this has to be the last. All TExecState reset!
    {$ifndef FPCONLY}
    //Any cross compilation; must be at end because it resets state machine run memory
    'Do LCLCross;'+
    {$endif}
    'End;'+

//cross sequence for win32. Note: if changing this name,
    //also change checks for this in skipmodules etc.
    'Declare crosswin64-32;'+
    'SetCPU i386;'+
    'SetOS win32;'+
    //Getmodule has already been done
    'Cleanmodule fpc;'+
    'Buildmodule fpc;'+
    {$ifndef FPCONLY}
    //Getmodule has already been done
    // Don't use cleanmodule; make distclean will remove lazbuild.exe etc
    //'Cleanmodule LCL;'+
    'Buildmodule LCL;'+
    {$endif}
    'End;'+

    //default sequence for ARM: some packages give errors and memory is limited, so keep it simple
    'Declare defaultARM;'+
    {$ifndef FPCONLY}
    'Exec CheckDevLibs;'+ //keyword Exec executes a function/procedure; must be defined in TSequencer.DoExec
    {$endif}
    'Do fpc;'+
    {$ifndef FPCONLY}
    'Do lazarus;'+
    {$endif}
    'End;'+

//default clean sequence
    'Declare defaultclean;'+
    'Do fpcclean;'+
    {$ifndef FPCONLY}
    'Do lazarusclean;'+
    'Do helplazarusclean;'+
    //'CleanModule DOCEDITOR;'+
    'Do UniversalDefaultClean;'+
    {$endif}
    'End;'+
    {
// Currently, make distclean LCL removes lazbuild.exe/lazarus.exe as well
// Then, universal installer won't work because of missing lazbuild, and of
// course Lazarus won't work either.
// Workaround: don't clean up.
//default clean sequence for win32
    'Declare defaultwin32clean;'+
    'Do fpcclean;'+
    {$ifndef FPCONLY}
    'Do lazarusclean;'+
    'Do helplazarusclean;'+
    //'CleanModule DOCEDITOR;'+
    'Do UniversalDefaultClean;'+
    {$endif}
    'Do crosswin32-64Clean;'+   //this has to be the last. All TExecState reset!
    'End;'+
//default cross clean sequence for win32
    'Declare crosswin32-64Clean;'+
    'SetCPU x86_64;'+
    'SetOS win64;'+
    'Cleanmodule fpc;'+
    {$ifndef FPCONLY}
    'Cleanmodule lazarus;'+
    {$endif}
    'End;'+
//default cross clean sequence for win64
    'Declare crosswin64-32Clean;'+
    'SetCPU i386;'+
    'SetOS win32;'+
    'Cleanmodule fpc;'+
    {$ifndef FPCONLY}
    'Cleanmodule lazarus;'+
    {$endif}
    'End;'+
    }

//default uninstall sequence
    'Declare defaultuninstall;'+
    'Do fpcuninstall;'+
    {$ifndef FPCONLY}
    'Do lazarusuninstall;'+
    'Do helpuninstall;'+
    //'UninstallModule DOCEDITOR;'+
    'Do UniversalDefaultUnInstall;'+
    {$endif}
    'End;'+
//default uninstall sequence for win32
    'Declare defaultwin32uninstall;'+
    'Do defaultuninstall;'+
    'End;'+
//default uninstall sequence for win64
    'Declare defaultwin64uninstall;'+
    'Do defaultuninstall;'+
    'End;';

type

  // from systems.inc
  tsystemcpu=
         (
               cpu_no,                       { 0 }
               cpu_i386,                     { 1 }
               cpu_m68k,                     { 2 }
               cpu_alpha,                    { 3 }
               cpu_powerpc,                  { 4 }
               cpu_sparc,                    { 5 }
               cpu_vm,                       { 6 }
               cpu_iA64,                     { 7 }
               cpu_x86_64,                   { 8 }
               cpu_mipseb,                   { 9 }
               cpu_arm,                      { 10 }
               cpu_powerpc64,                { 11 }
               cpu_avr,                      { 12 }
               cpu_mipsel,                   { 13 }
               cpu_jvm,                      { 14 }
               cpu_i8086,                    { 15 }
               cpu_aarch64,                  { 16 }
               cpu_wasm,                     { 17 }
               cpu_sparc64                   { 18 }
         );


  // from fpmake + fpmkunit !

  TCpu=(cpuNone,
      i386,m68k,powerpc,sparc,x86_64,arm,powerpc64,avr,armeb,
      mips,mipsel,jvm,i8086,aarch64
    );
  TCPUS = Set of TCPU;
  TOS=(osNone,
      linux,go32v2,win32,os2,freebsd,beos,netbsd,
      amiga,atari, solaris, qnx, netware, openbsd,wdosx,
      palmos,macos,darwin,emx,watcom,morphos,netwlibc,
      win64,wince,gba,nds,embedded,symbian,haiku,iphonesim,
      aix,java,android,nativent,msdos,wii,aros,dragonfly,
      win16
    );
  TOSes = Set of TOS;

Const
  // Aliases
  Amd64   = X86_64;
  PPC = PowerPC;
  PPC64 = PowerPC64;
  DOS = Go32v2;
  MacOSX = Darwin;

  AllOSes = [Low(TOS)..High(TOS)];
  AllCPUs = [Low(TCPU)..High(TCPU)];
  AllUnixOSes  = [Linux,FreeBSD,NetBSD,OpenBSD,Darwin,QNX,BeOS,Solaris,Haiku,iphonesim,aix,Android,dragonfly];
  AllBSDOSes      = [FreeBSD,NetBSD,OpenBSD,Darwin,iphonesim,dragonfly];
  AllWindowsOSes  = [Win32,Win64,WinCE];
  AllAmigaLikeOSes = [Amiga,MorphOS,AROS];
  AllLimit83fsOses = [go32v2,os2,emx,watcom,msdos,win16];

  AllSmartLinkLibraryOSes = [Linux,msdos,amiga,morphos,aros,win16]; // OSes that use .a library files for smart-linking
  AllImportLibraryOSes = AllWindowsOSes + [os2,emx,netwlibc,netware,watcom,go32v2,macos,nativent,msdos,win16];

  OSCPUSupported : array[TOS,TCpu] of boolean = (
    { os          none   i386    m68k  ppc    sparc  x86_64 arm    ppc64  avr    armeb  mips   mipsel jvm    i8086  aarch64 }
    { none }    ( false, false, false, false, false, false, false, false, false, false, false, false, false, false, false),
    { linux }   ( false, true,  true,  true,  true,  true,  true,  true,  false, true , true , true , false, false, true ),
    { go32v2 }  ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { win32 }   ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { os2 }     ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { freebsd } ( false, true,  true,  false, false, true,  false, false, false, false, false, false, false, false, false),
    { beos }    ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { netbsd }  ( false, true,  true,  true,  true,  true,  false, false, false, false, false, false, false, false, false),
    { amiga }   ( false, false, true,  true,  false, false, false, false, false, false, false, false, false, false, false),
    { atari }   ( false, false, true,  false, false, false, false, false, false, false, false, false, false, false, false),
    { solaris } ( false, true,  false, false, true,  true,  false, false, false, false, false, false, false, false, false),
    { qnx }     ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { netware } ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { openbsd } ( false, true,  true,  false, false, true,  false, false, false, false, false, false, false, false, false),
    { wdosx }   ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { palmos }  ( false, false, true,  false, false, false, true,  false, false, false, false, false, false, false, false),
    { macos }   ( false, false, false, true,  false, false, false, false, false, false, false, false, false, false, false),
    { darwin }  ( false, true,  false, true,  false, true,  true,  true,  false, false, false, false, false, false, true ),
    { emx }     ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { watcom }  ( false, true,  false, false, false ,false, false, false, false, false, false, false, false, false, false),
    { morphos } ( false, false, false, true,  false ,false, false, false, false, false, false, false, false, false, false),
    { netwlibc }( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { win64   } ( false, false, false, false, false, true,  false, false, false, false, false, false, false, false, false),
    { wince    }( false, true,  false, false, false, false, true,  false, false, false, false, false, false, false, false),
    { gba    }  ( false, false, false, false, false, false, true,  false, false, false, false, false, false, false, false),
    { nds    }  ( false, false, false, false, false, false, true,  false, false, false, false, false, false, false, false),
    { embedded }( false, true,  true,  true,  true,  true,  true,  true,  true,  true , false, false, false, true , false),
    { symbian } ( false, true,  false, false, false, false, true,  false, false, false, false, false, false, false, false),
    { haiku }   ( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { iphonesim}( false, true,  false, false, false, true,  false, false, false, false, false, false, false, false, false),
    { aix    }  ( false, false, false, true,  false, false, false, true,  false, false, false, false, false, false, false),
    { java }    ( false, false, false, false, false, false, false, false, false, false, false, false, true , false, false),
    { android } ( false, true,  false, false, false, false, true,  false, false, false, false, true,  true , false, false),
    { nativent }( false, true,  false, false, false, false, false, false, false, false, false, false, false, false, false),
    { msdos }   ( false, false, false, false, false, false, false, false, false, false, false, false, false, true , false),
    { wii }     ( false, false, false, true , false, false, false, false, false, false, false, false, false, false, false),
    { aros }    ( true,  false, false, false, false, false, true,  false, false, false, false, false, false, false, false),
    { dragonfly}( false, false, false, false, false, true,  false, false, false, false, false, false, false, false, false),
    { win16 }   ( false, false, false, false, false, false, false, false, false, false, false, false, false, true , false)
  );

type
  //TCPUBase = (i386,x86_64,arm,aarch64,powerpc,powerpc64,jvm,sparc,aix,mips,avr,m68k);
  TCPUBaseSet = set of TCPU;
  //TOSBase  = (windows,linux,android,darwin,freebsd,netbsd,ios,iphonesim,wince,java,embedded,dos,aros,haiku,go32,os2,solaris,amiga,atari);
  TOSBaseSet = set of TOS;

const

  // list of what fpcupdeluxe is able to do !!
  // this makes the user interaction better, by leaving out non-options

  {$ifdef BSD}
  {$ifdef Darwin}
  {$define CPUOSSetDefined}
  CPUset : TCPUBaseSet = [i386,x86_64,arm,aarch64];
  OSset  : TOSBaseSet  = [win32,darwin];
  {$else}
  {$define CPUOSSetDefined}
  CPUset : TCPUBaseSet = [i386,x86_64,arm,aarch64];
  OSset  : TOSBaseSet  = [win32,darwin];
  {$endif}
  {$endif}

  {$ifdef MsWindows}
  {$define CPUOSSetDefined}
  {$ifdef CPUX86}
  {$define CPUOSSetDefined}
  CPUset : TCPUBaseSet = [i386,x86_64,arm,aarch64,jvm];
  OSset  : TOSBaseSet  = [win32,linux,android,darwin,freebsd,wince,java];
  {$endif CPUX86}
  {$ifdef CPUX64}
  CPUset : TCPUBaseSet = [x86_64,arm,aarch64,jvm];
  OSset  : TOSBaseSet  = [win32,linux,android,darwin,freebsd,wince,java];
  {$endif CPUX64}
  {$endif}

  {$ifdef Linux}
  {$ifdef CPUX86}
  {$define CPUOSSetDefined}
  CPUset : TCPUBaseSet = [i386,x86_64,arm,aarch64];
  OSset  : TOSBaseSet  = [win32,linux,android,darwin,freebsd,java];
  {$endif CPUX86}
  {$ifdef CPUX64}
  {$define CPUOSSetDefined}
  CPUset : TCPUBaseSet = [i386,x86_64,arm,aarch64];
  OSset  : TOSBaseSet  = [win32,linux,android,darwin,freebsd,java];
  {$endif CPUX64}
  {$ifdef CPUARM}
  {$endif CPUARM}
  {$ifdef CPUAARCH64}
  {$endif CPUAARCH64}
  {$endif}

  {$ifndef CPUOSSetDefined}
  CPUset : TCPUBaseSet = [];
  OSset : TOSBaseSet = [];
  {$endif}

type

  TSequencer=class; //forward

  TResultCodes=(rMissingCrossLibs,rMissingCrossBins);
  TResultSet = Set of TResultCodes;

  { TFPCupManager }

  TFPCupManager=class(Tobject)
  private
    FResultSet:TResultSet;
    FSVNExecutable: string;
    FHTTPProxyHost: string;
    FHTTPProxyPassword: string;
    FHTTPProxyPort: integer;
    FHTTPProxyUser: string;
    FPersistentOptions: string;
    FBaseDirectory: string;
    FBootstrapCompiler: string;
    FBootstrapCompilerDirectory: string;
    FBootstrapCompilerURL: string;
    FClean: boolean;
    FCompilerName: string;
    FConfigFile: string;
    FCrossCPU_Target: string;
    {$ifndef FPCONLY}
    FCrossLCL_Platform: string; //really LCL widgetset
    {$endif}
    FCrossOPT: string;
    FCrossOS_Target: string;
    FCrossOS_SubArch: string;
    FFPCDesiredRevision: string;
    FFPCDesiredBranch: string;
    FFPCSourceDirectory: string;
    FFPCInstallDirectory: string;
    FFPCOPT: string;
    FFPCURL: string;
    FIncludeModules: string;
    FKeepLocalDiffs: boolean;
    {$ifndef FPCONLY}
    FLazarusDesiredRevision: string;
    FLazarusDesiredBranch: string;
    FLazarusDirectory: string;
    FLazarusOPT: string;
    FLazarusPrimaryConfigPath: string;
    FLazarusURL: string;
    {$endif}
    FCrossToolsDirectory: string;
    FCrossLibraryDirectory: string;
    FMakeDirectory: string;
    FOnlyModules: string;
    FPatchCmd: string;
    FReApplyLocalChanges: boolean;
    {$ifndef FPCONLY}
    FShortCutNameLazarus: string;
    {$endif}
    FShortCutNameFpcup: string;
    FSkipModules: string;
    FFPCPatches:string;
    {$ifndef FPCONLY}
    FLazarusPatches:string;
    {$endif}
    FUninstall:boolean;
    FVerbose: boolean;
    FUseWget: boolean;
    FExportOnly:boolean;
    FNoJobs:boolean;
    FUseGitClient:boolean;
    FSequencer: TSequencer;
    {$ifndef FPCONLY}
    function GetLazarusPrimaryConfigPath: string;
    procedure SetLazarusDirectory(AValue: string);
    procedure SetLazarusURL(AValue: string);
    {$endif}
    function GetLogFileName: string;
    procedure SetBaseDirectory(AValue: string);
    procedure SetBootstrapCompilerDirectory(AValue: string);
    procedure SetFPCSourceDirectory(AValue: string);
    procedure SetFPCInstallDirectory(AValue: string);
    procedure SetFPCURL(AValue: string);
    procedure SetCrossToolsDirectory(AValue: string);
    procedure SetCrossLibraryDirectory(AValue: string);
    procedure SetLogFileName(AValue: string);
    procedure SetMakeDirectory(AValue: string);
    function GetUseWget:boolean;
  protected
    FLog:TLogger;
    FModuleList:TStringList;
    FModuleEnabledList:TStringList;
    FModulePublishedList:TStringList;
    // Write msg to log with line ending. Can also write to console
    procedure WritelnLog(msg:string;ToConsole:boolean=true);overload;
    procedure WritelnLog(EventType: TEventType;msg:string;ToConsole:boolean=true);overload;
 public
    property ResultSet: TResultSet read FResultSet;
    property Sequencer: TSequencer read FSequencer;
   {$ifndef FPCONLY}
    property ShortCutNameLazarus: string read FShortCutNameLazarus write FShortCutNameLazarus; //Name of the shortcut that points to the fpcup-installed Lazarus
    {$endif}
    property ShortCutNameFpcup:string read FShortCutNameFpcup write FShortCutNameFpcup; //Name of the shortcut that points to fpcup
    // Full path+filename of SVN executable. Use empty to search for default locations.
    property SVNExecutable: string read FSVNExecutable write FSVNExecutable;
    property CompilerName: string read FCompilerName write FCompilerName;
    // Options that are to be saved in shortcuts/batch file/shell scripts.
    // Excludes temporary options like --verbose
    property PersistentOptions: string read FPersistentOptions write FPersistentOptions;
    // Full path to bootstrap compiler
    property BootstrapCompiler: string read FBootstrapCompiler write FBootstrapCompiler;
    property BaseDirectory: string read FBaseDirectory write SetBaseDirectory;
    // Directory where bootstrap compiler is installed/downloaded
    property BootstrapCompilerDirectory: string read FBootstrapCompilerDirectory write SetBootstrapCompilerDirectory;
    // URL to download the bootstrap compiler from
    property BootstrapCompilerURL: string read FBootstrapCompilerURL write FBootstrapCompilerURL;
    property Clean: boolean read FClean write FClean;
    property ConfigFile: string read FConfigFile write FConfigFile;
    property CrossCPU_Target:string read FCrossCPU_Target write FCrossCPU_Target;
    // Widgetset for which the user wants to compile the LCL (not the IDE).
    // Empty if default LCL widgetset used for current platform
    {$ifndef FPCONLY}
    property CrossLCL_Platform:string read FCrossLCL_Platform write FCrossLCL_Platform;
    {$endif}
    property CrossOPT:string read FCrossOPT write FCrossOPT;
    property CrossOS_Target:string read FCrossOS_Target write FCrossOS_Target;
    property CrossOS_SubArch:string read FCrossOS_SubArch write FCrossOS_SubArch;
    property CrossToolsDirectory:string read FCrossToolsDirectory write SetCrossToolsDirectory;
    property CrossLibraryDirectory:string read FCrossLibraryDirectory write SetCrossLibraryDirectory;
    property FPCSourceDirectory: string read FFPCSourceDirectory write SetFPCSourceDirectory;
    property FPCInstallDirectory: string read FFPCInstallDirectory write SetFPCInstallDirectory;
    property FPCURL: string read FFPCURL write SetFPCURL;
    property FPCOPT: string read FFPCOPT write FFPCOPT;
    property FPCDesiredRevision: string read FFPCDesiredRevision write FFPCDesiredRevision;
    property FPCDesiredBranch: string read FFPCDesiredBranch write FFPCDesiredBranch;
    property HTTPProxyHost: string read FHTTPProxyHost write FHTTPProxyHost;
    property HTTPProxyPassword: string read FHTTPProxyPassword write FHTTPProxyPassword;
    property HTTPProxyPort: integer read FHTTPProxyPort write FHTTPProxyPort;
    property HTTPProxyUser: string read FHTTPProxyUser write FHTTPProxyUser;
    property KeepLocalChanges: boolean read FKeepLocalDiffs write FKeepLocalDiffs;
   {$ifndef FPCONLY}
    property LazarusDirectory: string read FLazarusDirectory write SetLazarusDirectory;
    property LazarusPrimaryConfigPath: string read GetLazarusPrimaryConfigPath write FLazarusPrimaryConfigPath ;
    property LazarusURL: string read FLazarusURL write SetLazarusURL;
    property LazarusOPT:string read FLazarusOPT write FLazarusOPT;
    property LazarusDesiredRevision:string read FLazarusDesiredRevision write FLazarusDesiredRevision;
    property LazarusDesiredBranch:string read FLazarusDesiredBranch write FLazarusDesiredBranch;
    {$endif}
    // Location where fpcup log will be written to.
    property LogFileName: string read GetLogFileName write SetLogFileName;
    // Directory where make is. Can be empty.
    // On Windows, also a directory where the binutils can be found.
    property MakeDirectory: string read FMakeDirectory write SetMakeDirectory;
    // List of all default enabled sequences available
    property ModuleEnabledList: TStringList read FModuleEnabledList;
    // List of all publicly visible sequences
    property ModulePublishedList: TStringList read FModulePublishedList;
    // List of modules that must be processed in addition to the default ones
    property IncludeModules:string read FIncludeModules write FIncludeModules;
    // Patch utility to use. Defaults to '(g)patch'
    property PatchCmd:string read FPatchCmd write FPatchCmd;
    // Whether or not to back up locale changes to .diff and reapply them before compiling
    property ReApplyLocalChanges: boolean read FReApplyLocalChanges write FReApplyLocalChanges;
    // List of modules that must not be processed
    property SkipModules:string read FSkipModules write FSkipModules;
    property FPCPatches:string read FFPCPatches write FFPCPatches;
    {$ifndef FPCONLY}
    property LazarusPatches:string read FLazarusPatches write FLazarusPatches;
    {$endif}
    // Exhaustive/exclusive list of modules that must be processed; no other
    // modules may be processed.
    property OnlyModules:string read FOnlyModules write FOnlyModules;
    property Uninstall: boolean read FUninstall write FUninstall;
    property Verbose:boolean read FVerbose write FVerbose;
    property UseWget:boolean read GetUseWget write FUseWget;
    property ExportOnly:boolean read FExportOnly write FExportOnly;
    property NoJobs:boolean read FNoJobs write FNoJobs;
    property UseGitClient:boolean read FUseGitClient write FUseGitClient;
    // Fill in ModulePublishedList and ModuleEnabledList and load other config elements
    function LoadFPCUPConfig:boolean;
    // Stop talking. Do it! Returns success status
    function Run: boolean;

    constructor Create;
    destructor Destroy; override;
  end;


  // Was this sequence already executed before? Which result?
  TExecState=(ESNever,ESFailed,ESSucceeded);

  TSequenceAttributes=record
    EntryPoint:integer;  //instead of rescanning the sequence table everytime, we can as well store the index in the table
    Executed:TExecState; //  Reset to ESNever at sequencer start up
  end;
  PSequenceAttributes=^TSequenceAttributes;

  TKeyword=(SMdeclare, SMdeclareHidden, SMdo, SMrequire, SMexec, SMend, SMcleanmodule, SMgetmodule, SMbuildmodule,
    SMuninstallmodule, SMconfigmodule{$ifndef FPCONLY}, SMResetLCL{$endif}, SMSetOS, SMSetCPU, SMInvalid);

  TState=record
    instr:TKeyword;
    param:string;
    end;

  { TSequencer }

  TSequencer=class(TObject)
    protected
      FParent:TFPCupManager;
      FCurrentModule:String;
      FInstaller:TInstaller;  //current installer
      FSkipList:TStringList;
      FStateMachine:array of TState;
      procedure AddToModuleList(ModuleName:string;EntryPoint:integer);
      function DoBuildModule(ModuleName:string):boolean;
      function DoCleanModule(ModuleName:string):boolean;
      function DoConfigModule(ModuleName:string):boolean;
      function DoExec(FunctionName:string):boolean;
      function DoGetModule(ModuleName:string):boolean;
      function DoSetCPU(CPU:string):boolean;
      function DoSetOS(OS:string):boolean;
      // Resets memory of executed steps so LCL widgetset can be rebuild
      // e.g. using different platform
      {$ifndef FPCONLY}
      function DoResetLCL:boolean;
      {$endif}
      function DoUnInstallModule(ModuleName:string):boolean;
      function GetInstaller(ModuleName:string):boolean;
      function GetText:string;
      function IsSkipped(ModuleName:string):boolean;
      // Reset memory of executed steps, allowing sequences with e.g. new OS to be rerun
    public
      // set Executed to ESNever for all sequences
      procedure ResetAllExecuted(SkipFPC:boolean=false);
      property Parent:TFPCupManager write FParent;
      property Installer:TInstaller read FInstaller;
      // Text representation of sequence; for diagnostic purposes
      property Text:String read GetText;
      // parse a sequence source code and append to the FStateMachine
      function AddSequence(Sequence:string):boolean;
      // Add the "only" sequence from the FStateMachine based on the --only list
      function CreateOnly(OnlyModules:string):boolean;
      // deletes the "only" sequence from the FStateMachine
      function DeleteOnly:boolean;
      // run the FStateMachine starting at SequenceName
      function Run(SequenceName:string):boolean;
      constructor Create;
      destructor Destroy; override;
    end;

implementation

{$ifdef linux}
uses
  processutils;
{$endif}

{ TFPCupManager }

{$ifndef FPCONLY}
function TFPCupManager.GetLazarusPrimaryConfigPath: string;
const
  // This should be a last resort as FLazarusPrimaryConfigPath should be used really
  DefaultPCPSubdir='lazarusdevsettings'; //Include the name lazarus for easy searching Caution: shouldn't be the same name as Lazarus dir itself.
begin
  if FLazarusPrimaryConfigPath='' then
  begin
    {$IFDEF MSWINDOWS}
    // Somewhere in local appdata special folder
    FLazarusPrimaryConfigPath:=ExcludeTrailingPathDelimiter(GetLocalAppDataPath())+DefaultPCPSubdir;
    {$ELSE}
    // Note: normal GetAppConfigDir gets ~/.config/fpcup/.lazarusdev or something
    // XdgConfigHome normally resolves to something like ~/.config
    // which is a reasonable default if we have no Lazarus primary config path set
    FLazarusPrimaryConfigPath:=ExcludeTrailingPathDelimiter(XdgConfigHome)+DefaultPCPSubdir;
    {$ENDIF MSWINDOWS}
  end;
  result:=FLazarusPrimaryConfigPath;
end;
{$endif}

function TFPCupManager.GetLogFileName: string;
begin
  result:=FLog.LogFile;
end;

procedure TFPCupManager.SetBaseDirectory(AValue: string);
begin
  FBaseDirectory:=SafeExpandFileName(AValue);
end;

procedure TFPCupManager.SetBootstrapCompilerDirectory(AValue: string);
begin
  FBootstrapCompilerDirectory:=ExcludeTrailingPathDelimiter(SafeExpandFileName(AValue));
end;

procedure TFPCupManager.SetFPCSourceDirectory(AValue: string);
begin  
  FFPCSourceDirectory:=SafeExpandFileName(AValue);
end;

procedure TFPCupManager.SetFPCInstallDirectory(AValue: string);
begin
  FFPCInstallDirectory:=SafeExpandFileName(AValue);
end;


procedure TFPCupManager.SetFPCURL(AValue: string);
begin
  if FFPCURL=AValue then Exit;
  if pos('//',AValue)>0 then
    FFPCURL:=AValue
  else
    FFPCURL:=installerUniversal.GetAlias('fpcURL',AValue);
end;


procedure TFPCupManager.SetCrossToolsDirectory(AValue: string);
begin
  //FCrossToolsDirectory:=SafeExpandFileName(AValue);
  FCrossToolsDirectory:=AValue;
end;

procedure TFPCupManager.SetCrossLibraryDirectory(AValue: string);
begin
  //FCrossLibraryDirectory:=SafeExpandFileName(AValue);
  FCrossLibraryDirectory:=AValue;
end;

{$ifndef FPCONLY}
procedure TFPCupManager.SetLazarusDirectory(AValue: string);
begin
  FLazarusDirectory:=SafeExpandFileName(AValue);
end;

procedure TFPCupManager.SetLazarusURL(AValue: string);
begin
  if FLazarusURL=AValue then Exit;
  if pos('//',AValue)>0 then
    FLazarusURL:=AValue
  else
    FLazarusURL:=installerUniversal.GetAlias('lazURL',AValue);
end;
{$endif}

procedure TFPCupManager.SetLogFileName(AValue: string);
begin
  // Don't change existing log file
  if (AValue<>'') and (FLog.LogFile=AValue) then Exit;
  // Defaults if empty value specified
  if AValue='' then
    begin
    {$IFDEF MSWINDOWS}
    FLog.LogFile:=SafeGetApplicationPath+'fpcup.log'; //exe directory
    {$ELSE}
    FLog.LogFile:=SafeExpandFileNameUTF8('~')+DirectorySeparator+'fpcup.log'; //home directory
    {$ENDIF MSWINDOWS}
    end
  else
    begin
    FLog.LogFile:=AValue;
    end;
end;

procedure TFPCupManager.SetMakeDirectory(AValue: string);
begin
  FMakeDirectory:=SafeExpandFileName(AValue);
end;

function TFPCupManager.GetUseWget:boolean;
begin
  {$ifdef OpenBSD}
  // only curl / wget works on OpenBSD (yet)
  result:=True;
  {$else}
  result:=FUseWget;
  {$endif}
end;

procedure TFPCupManager.WritelnLog(msg: string; ToConsole: boolean);
begin
  // Set up log if it doesn't exist yet
  FLog.WriteLog(msg,ToConsole);
end;

procedure TFPCupManager.WritelnLog(EventType: TEventType; msg: string; ToConsole: boolean);
begin
  // Set up log if it doesn't exist yet
  FLog.WriteLog(EventType,msg,ToConsole);
end;


function TFPCupManager.LoadFPCUPConfig: boolean;
begin
  installerUniversal.SetConfigFile(FConfigFile);
  FSequencer.AddSequence(Sequences);
  FSequencer.AddSequence(installerFPC.Sequences);
  {$ifndef FPCONLY}
  FSequencer.AddSequence(installerLazarus.Sequences);
  {$endif}
  FSequencer.AddSequence(installerHelp.Sequences);
  FSequencer.AddSequence(installerUniversal.Sequences);
  // append universal modules to the lists
  FSequencer.AddSequence(installerUniversal.GetModuleList);
  result:=installerUniversal.GetModuleEnabledList(FModuleEnabledList);
end;

function TFPCupManager.Run: boolean;
{$IFDEF MSWINDOWS}
var
  Major:integer=0;
  Minor:integer=0;
  Build:integer=0;
{$ENDIF}
begin
  result:=false;

  if
    (lowercase(FSequencer.FParent.CrossCPU_Target)=GetTargetCPU)
    AND
    (lowercase(FSequencer.FParent.CrossOS_Target)=GetTargetOS)
  then
  begin
    infoln('No crosscompiling to own target !!',etError);
    exit;
  end;

  FResultSet:=[];

  try
    WritelnLog(DateTimeToStr(now)+': fpcup'+RevisionStr+' ('+VersionDate+') started.',true);
  except
    // Writing to log failed, probably duplicate run. Inform user and get out.
    {$IFNDEF NOCONSOLE}
    writeln('***ERROR***');
    writeln('Could not open log file '+FLog.LogFile+' for writing.');
    writeln('Perhaps another fpcup is running?');
    writeln('Aborting.');
    {$ENDIF}
    halt(2);
  end;

  infoln('InstallerManager: current sequence: '+LineEnding+
    FSequencer.Text,etDebug);

  // Some diagnostic info
  {$IFDEF MSWINDOWS}
  if Verbose then
    if GetWin32Version(Major,Minor,Build) then
    begin
      infoln('Windows major version: '+inttostr(Major),etInfo);
      infoln('Windows minor version: '+inttostr(Minor),etInfo);
      infoln('Windows build number:  '+inttostr(Build),etInfo);
    end
    else
      infoln('Could not retrieve Windows version using GetWin32Version.',etWarning);
  {$ENDIF}

  FSequencer.FSkipList:=nil;
  if SkipModules<>'' then
  begin
    FSequencer.FSkipList:=TStringList.Create;
    FSequencer.FSkipList.Delimiter:=',';
    FSequencer.FSkipList.DelimitedText:=SkipModules;
  end;

  if FOnlyModules<>'' then
  begin
    FSequencer.CreateOnly(FOnlyModules);
    result:=FSequencer.Run('Only');
    FSequencer.DeleteOnly;
  end
  else
  begin
    {$if defined(win32)}
    // Run Windows specific cross compiler or regular version
    if pos('CROSSWIN32-64',UpperCase(SkipModules))>0 then begin
      infoln('InstallerManager: going to run sequencer for sequence: Default.',etDebug);
      result:=FSequencer.Run('Default');
    end
    else
    begin
      infoln('InstallerManager: going to run sequencer for sequence: DefaultWin32.',etDebug);
      result:=FSequencer.Run('DefaultWin32');
    end;
    // We would like to have a win64=>win32 crosscompiler, but at least with current
    // FPC trunk that won't work due to errors like
    // fpcdefs.inc(216,2) Error: User defined: Cross-compiling from systems
    // without support for an 80 bit extended floating point type to i386 is
    // not yet supported at this time. If it is, uncomment until the else conditional:
    //{$elseif defined(win64)}
    {
    if pos('CROSSWIN64-32',UpperCase(SkipModules))>0 then
      result:=FSequencer.Run('Default')
    else
      result:=FSequencer.Run('DefaultWin64');
    }
    {$else}

    // Linux, OSX
    {$ifdef CPUAARCH64}
    // some default packages do not work yet on aarch64 (03-2016)
    infoln('InstallerManager: going to run fpc+lazarus sequencer for sequence ARM64 (just plain Lazarus)',etDebug);
    result:=FSequencer.Run('defaultARM');
    {$else}
      {$ifdef cpuarm}
      infoln('InstallerManager: going to run sequencer for sequence ARM (without help files)',etDebug);
      result:=FSequencer.Run('defaultARM');
      {$else}
      infoln('InstallerManager: going to run sequencer for sequence Default.',etDebug);
      result:=FSequencer.Run('Default');
      {$endif}
    {$endif}

    {$endif}
    if (FIncludeModules<>'') and (result) then begin
      // run specified additional modules using the only mechanism
      infoln('InstallerManager: going to run sequencer for include modules '+FIncludeModules,etDebug);
      FSequencer.CreateOnly(FIncludeModules);
      result:=FSequencer.Run('Only');
      FSequencer.DeleteOnly;
    end;
  end;

  //FResultSet:=FSequencer.FInstaller;

  if assigned(FSequencer.FSkipList) then FSequencer.FSkipList.Free;
end;

constructor TFPCupManager.Create;
begin
  Verbose:=false;
  UseWget:=false;
  ExportOnly:=false;
  NoJobs:=false;
  UseGitClient:=false;

  FModuleList:=TStringList.Create;
  FModuleEnabledList:=TStringList.Create;
  FModulePublishedList:=TStringList.Create;
  FSequencer:=TSequencer.create;
  FSequencer.Parent:=Self;
  FLog:=TLogger.Create;
  // Log filename will be set on first log write
end;

destructor TFPCupManager.Destroy;
var i:integer;
begin
  for i:=0 to FModuleList.Count-1 do
    Freemem(FModuleList.Objects[i]);
  FModuleList.Free;
  FModulePublishedList.Free;
  FModuleEnabledList.Free;
  FSequencer.free;
  try
    WritelnLog(DateTimeToStr(now)+': fpcup finished.',true);
    WritelnLog('------------------------------------------------',false);
  finally
    //ignore logging errors
  end;
  FLog.Free;
  inherited Destroy;
end;

{ TSequencer }

procedure TSequencer.AddToModuleList(ModuleName: string; EntryPoint: integer);
var
  SeqAttr:PSequenceAttributes;
begin
  getmem(SeqAttr,sizeof(TSequenceAttributes));
  SeqAttr^.EntryPoint:=EntryPoint;
  SeqAttr^.Executed:=ESNever;
  FParent.FModuleList.AddObject(ModuleName,TObject(SeqAttr));
end;

function TSequencer.DoBuildModule(ModuleName: string): boolean;
begin
  infoln('TSequencer: DoBuildModule for module '+ModuleName+' called.',etDebug);
  result:= GetInstaller(ModuleName) and FInstaller.BuildModule(ModuleName);
end;

function TSequencer.DoCleanModule(ModuleName: string): boolean;
begin
  infoln('TSequencer: DoCleanModule for module '+ModuleName+' called.',etDebug);
  result:= GetInstaller(ModuleName) and FInstaller.CleanModule(ModuleName);
end;

function TSequencer.DoConfigModule(ModuleName: string): boolean;
begin
  infoln('TSequencer: DoConfigModule for module '+ModuleName+' called.',etDebug);
  result:= GetInstaller(ModuleName) and FInstaller.ConfigModule(ModuleName);
end;

function TSequencer.DoExec(FunctionName: string): boolean;

  function CreateFpcupScript:boolean;
  begin
    result:=true;
    // Link to fpcup itself, with all options as passed when invoking it:
    if FParent.ShortCutNameFpcup<>EmptyStr then
    begin
     {$IFDEF MSWINDOWS}
      CreateDesktopShortCut(SafeGetApplicationPath+ExtractFileName(paramstr(0)),FParent.PersistentOptions,FParent.ShortCutNameFpcup);
     {$ELSE}
      FParent.PersistentOptions:=FParent.PersistentOptions+' $*';
      CreateHomeStartLink('"'+SafeGetApplicationPath+ExtractFileName(paramstr(0))+'"',FParent.PersistentOptions,FParent.ShortCutNameFpcup);
     {$ENDIF MSWINDOWS}
    end;
  end;

  {$ifndef FPCONLY}
  function CreateLazarusScript:boolean;
  // Find out InstalledLazarus location, create desktop shortcuts etc
  // Don't use this function when lazarus is not installed.
  var
    InstalledLazarus:string;
  begin
  result:=true;
  if FParent.ShortCutNameLazarus<>EmptyStr then
  begin
    infoln('Lazarus: creating desktop shortcut:',etInfo);
    try
      // Create shortcut; we don't care very much if it fails=>don't mess with OperationSucceeded
      InstalledLazarus:=IncludeTrailingPathDelimiter(FParent.LazarusDirectory)+'lazarus'+GetExeExt;
      {$IFDEF MSWINDOWS}
      CreateDesktopShortCut(InstalledLazarus,'--pcp="'+FParent.LazarusPrimaryConfigPath+'"',FParent.ShortCutNameLazarus);
      {$ENDIF MSWINDOWS}
      {$IFDEF UNIX}
      {$IFDEF DARWIN}
      CreateHomeStartLink(IncludeLeadingPathDelimiter(InstalledLazarus)+'.app/Contents/MacOS/lazarus','--pcp="'+FParent.LazarusPrimaryConfigPath+'"',FParent.ShortcutNameLazarus);
      // Create shortcut on Desktop and in Applications
      fpSystem('/usr/bin/osascript << EOF'+#10+
               'tell application "Finder"'+#10+
               'set myLazApp to POSIX file "'+IncludeLeadingPathDelimiter(InstalledLazarus)+'.app" as alias'+#10+
               'try'+#10+
                 'set myLazDeskShort to (path to desktop folder as string) & "'+FParent.ShortCutNameLazarus+'" as alias'+#10+
               'on error'+#10+
                 'make new alias to myLazApp at (path to desktop folder as text)'+#10+
                 'set name of result to "'+FParent.ShortCutNameLazarus+'"'+#10+
               'end try'+#10+

               'try'+#10+
                 'set myLazAppShort to (path to applications folder as string) & "'+FParent.ShortCutNameLazarus+'" as alias'+#10+
               'on error'+#10+
                 'make new alias to myLazApp at (path to applications folder as text)'+#10+
                 'set name of result to "'+FParent.ShortCutNameLazarus+'"'+#10+
               'end try'+#10+

               'end tell'+#10+
               'EOF');
      {$ELSE}
      CreateHomeStartLink(InstalledLazarus,'--pcp="'+FParent.LazarusPrimaryConfigPath+'"',FParent.ShortcutNameLazarus);
      {$ENDIF DARWIN}
      {$IF (defined(LINUX)) or (defined(BSD))}
      // Desktop shortcut creation will not always work. As a fallback, create the link in the home directory:
      CreateDesktopShortCut(InstalledLazarus,'--pcp="'+FParent.LazarusPrimaryConfigPath+'"',FParent.ShortCutNameLazarus);
      CreateHomeStartLink('"'+InstalledLazarus+'"','--pcp="'+FParent.LazarusPrimaryConfigPath+'"',FParent.ShortcutNameLazarus);
      {$ENDIF (defined(LINUX)) or (defined(BSD))}
      {$ENDIF UNIX}
    except
      // Ignore problems creating shortcut
      infoln('CreateLazarusScript: Error creating shortcuts/links to Lazarus. Continuing.',etWarning);
    end;
  end;
  end;

  function DeleteLazarusScript:boolean;
  begin
  result:=true;
  if FParent.ShortCutNameLazarus<>EmptyStr then
  begin
    infoln('Lazarus: deleting desktop shortcut:',etInfo);
    try
      //Delete shortcut; we don't care very much if it fails=>don't mess with OperationSucceeded
      {$IFDEF MSWINDOWS}
      DeleteDesktopShortCut(FParent.ShortCutNameLazarus);
      {$ENDIF MSWINDOWS}
      {$IFDEF UNIX}
      DeleteFileUTF8(FParent.ShortcutNameLazarus);
      {$ENDIF UNIX}
    finally
      //Ignore problems deleting shortcut
    end;
  end;
  end;

  {$ifdef linux}
  function CheckDevLibs(LCLPlatform: string): boolean;
  const
    LIBSCNT=4;
  type
    TLibList=array[1..LIBSCNT] of string;
    LibSource = record
      lib:string;
      source:string;
    end;

  const
    LCLLIBS:TLibList = ('libX11.so','libgdk_pixbuf-2.0.so','libpango-1.0.so','libgdk-x11-2.0.so');
    QTLIBS:TLibList = ('libQt4Pas.so','','','');
  var
    i:integer;
    pll:^TLibList;
    Output: string;
    AdvicedLibs:string;
    AllOutput:TStringList;
    LS:array of LibSource;

    function TestLib(LibName:string):boolean;
    var
      Lib : TLibHandle;
    begin
      result:=true;
      if LibName<>'' then
        begin
        Lib:=LoadLibrary(LibName);
        result:=Lib<>0;
        if result then
          UnloadLibrary(Lib);
        end;
    end;

  begin
    result:=true;

    // these libs are always needed !!
    AdvicedLibs:='make gdb binutils unrar patch wget ';

    AllOutput:=TStringList.Create;
    try
      Output:='';
      ExecuteCommand('cat /etc/os-release',Output,false);
      AllOutput.Text := Output;
      Output := lowercase(AllOutput.Values['ID_LIKE']);
      if Length(Output)=0 then Output := lowercase(AllOutput.Values['DISTRIB_ID']);
      if Length(Output)=0 then Output := lowercase(AllOutput.Values['ID']);

      {$ifdef BSD}
      {$ifndef Darwin}
      if Length(Output)=0 then
      begin
        ExecuteCommand('uname -s',Output,false);
        Output := lowercase(Output);
      end;
      {$endif}
      {$endif}

      if (Output='arch') OR (Output='manjaro') then
      begin
        Output:='libx11 gtk2 gdk-pixbuf2 pango cairo';
        AdvicedLibs:=AdvicedLibs+'libx11 gtk2 gdk-pixbuf2 pango cairo ibus-gtk and ibus-gtk3 xorg-fonts-100dpi xorg-fonts-75dpi ttf-freefont ttf-liberation unrar';
      end
      else if (Output='debian') OR (Output='ubuntu') OR (Output='linuxmint') then
      begin
        {
        SetLength(LS,12);
        LS[0].lib:='libX11.so';
        LS[0].source:='libx11-dev' ;

        LS[1].lib:='libgdk_pixbuf-2.0.so';
        LS[1].source:='libgdk-pixbuf2.0-dev' ;

        LS[2].lib:='libgtk-x11-2.0.so';
        LS[2].source:='libgtk2.0-0';
        LS[3].lib:='libgdk-x11-2.0.so';
        LS[3].source:='libgtk2.0-0';

        LS[4].lib:='libgobject-2.0.so';
        LS[4].source:='libglib2.0-0';

        LS[5].lib:='libglib-2.0.so';
        LS[5].source:='libglib2.0-0';

        LS[6].lib:='libgthread-2.0.so';

        LS[7].lib:='libgmodule-2.0.so';

        LS[8].lib:='libpango-1.0.so';
        LS[8].source:='libpango1.0-dev';

        LS[9].lib:='libcairo.so';
        LS[8].source:='libcairo2-dev';

        LS[10].lib:='libatk-1.0.so';
        LS[10].source:='libatk1.0-dev';

        LS[11].lib:='libpangocairo-1.0.so';
        }
        //apt-get install subversion make binutils gdb gcc libgtk2.0-dev

        Output:='libx11-dev libgtk2.0-dev libcairo2-dev libpango1.0-dev libxtst-dev libgdk-pixbuf2.0-dev libatk1.0-dev libghc-x11-dev';
        AdvicedLibs:=AdvicedLibs+
                     'make binutils build-essential gdb gcc subversion unrar devscripts libc6-dev freeglut3-dev libgl1-mesa libgl1-mesa-dev '+
                     'libglu1-mesa libglu1-mesa-dev libgpmg1-dev libsdl-dev libXxf86vm-dev libxtst-dev '+
                     'libxft2 libfontconfig1 xfonts-scalable gtk2-engines-pixbuf unrar';
      end
      else
      if (Output='rhel') OR (Output='centos') OR (Output='scientific') OR (Output='fedora')  then
      begin
        Output:='libx11-devel gtk2-devel gtk+extra gtk+-devel cairo-devel cairo-gobject-devel pango-devel';
      end
      else
      if (Output='openbsd') then
      begin
        Output:='libiconv xorg-libraries libx11 libXtst xorg-fonts-type1 liberation-fonts-ttf gtkglext';
        //Output:='gmake gdk-pixbuf gtk+2';
      end
      else
      if (Output='freebsd') OR (Output='netbsd') then
      begin
        Output:='xorg-libraries libX11 libXtst gtkglext iconv xorg-fonts-type1 liberation-fonts-ttf';
      end
      else Output:='the libraries to get libX11.so and libgdk_pixbuf-2.0.so and libpango-1.0.so and libgdk-x11-2.0.so, but also make and binutils';

    finally
      AllOutput.Free;
    end;

    if (LCLPlatform='') or (Uppercase(LCLPlatform)='GTK2') then
      pll:=@LCLLIBS
    else if Uppercase(LCLPlatform)='QT' then
      pll:=@QTLIBS;
    for i:=1 to LIBSCNT do
    begin
      if not TestLib(pll^[i]) then
      begin
        FParent.WritelnLog(etError,'Required package is not installed for Lazarus: '+pll^[i], true);
        result:=false;
      end;
    end;
    if (NOT result) AND (Length(Output)>0) then
    begin
      FParent.WritelnLog(etError,'You need to install at least '+Output+' to build Lazarus !!', true);
      FParent.WritelnLog(etError,'Make, binutils, subversion/svn [and gdb] are also required !!', true);
    end;

    // do not error out ... user could only install FPC
    result:=true;

  end;
  {$else} //stub for other platforms for now
  function CheckDevLibs(LCLPlatform: string): boolean;
  begin
    result:=true;
  end;
  {$endif linux}
  {$endif}
begin
  infoln('TSequencer: DoExec for function '+FunctionName+' called.',etDebug);
  if UpperCase(FunctionName)='CREATEFPCUPSCRIPT' then
    result:=CreateFpcupScript
  {$ifndef FPCONLY}
  else if UpperCase(FunctionName)='CREATELAZARUSSCRIPT' then
    result:=CreateLazarusScript
  else if UpperCase(FunctionName)='DELETELAZARUSSCRIPT' then
    result:=DeleteLazarusScript
  else if UpperCase(FunctionName)='CHECKDEVLIBS' then
    result:=CheckDevLibs(FParent.CrossLCL_Platform)
  {$endif}
  else
    begin
    result:=false;
    FParent.WritelnLog('Error: Trying to execute a non existing function: ' + FunctionName);
    end;
end;

function TSequencer.DoGetModule(ModuleName: string): boolean;
begin
  infoln('TSequencer: DoGetModule for module '+ModuleName+' called.',etDebug);
  result:= GetInstaller(ModuleName) and FInstaller.GetModule(ModuleName);
end;

function TSequencer.DoSetCPU(CPU: string): boolean;
begin
  infoln('TSequencer: DoSetCPU for CPU '+CPU+' called.',etDebug);
  FParent.CrossCPU_Target:=CPU;
  ResetAllExecuted;
  result:=true;
end;

function TSequencer.DoSetOS(OS: string): boolean;
begin
  infoln('TSequencer: called DoSetOS for OS '+OS,etDebug);
  FParent.CrossOS_Target:=OS;
  ResetAllExecuted;
  result:=true;
end;

{$ifndef FPCONLY}
function TSequencer.DoResetLCL: boolean;
begin
  infoln('TSequencer: called DoReSetLCL',etDebug);
  ResetAllExecuted(true);
  result:=true;
end;
{$endif}

function TSequencer.DoUnInstallModule(ModuleName: string): boolean;
begin
  infoln('TSequencer: DoUninstallModule for module '+ModuleName+' called.',etDebug);
  result:= GetInstaller(ModuleName) and FInstaller.UnInstallModule(ModuleName);
end;

{GetInstaller gets a new installer for ModuleName and initialises parameters unless one exist already.}

function TSequencer.GetInstaller(ModuleName: string): boolean;
var
  CrossCompiling:boolean;
begin
  result:=true;
  CrossCompiling:=(FParent.CrossCPU_Target<>'') or (FParent.CrossOS_Target<>'');

  //check if this is a known module:

  // FPC:
  if (uppercase(ModuleName)='FPC') then
    begin
    if assigned(FInstaller) then
      begin
      // Check for existing normal compiler, or exact same cross compiler
      if (not crosscompiling and (FInstaller is TFPCNativeInstaller)) or
        ( crosscompiling and
        (FInstaller is TFPCCrossInstaller) and
        (FInstaller.CrossOS_Target=FParent.CrossOS_Target) and
        (FInstaller.CrossCPU_Target=FParent.CrossCPU_Target)
        ) then
        begin
        exit; //all fine, continue with current FInstaller
        end
      else
        FInstaller.free; // get rid of old FInstaller
      end;
    if CrossCompiling then
    begin
      FInstaller:=TFPCCrossInstaller.Create;
      FInstaller.CrossCPU_Target:=FParent.CrossCPU_Target;
      FInstaller.CrossOPT:=FParent.CrossOPT;
      FInstaller.CrossOS_Target:=FParent.CrossOS_Target;
      FInstaller.CrossOS_SubArch:=FParent.CrossOS_SubArch;
      FInstaller.CrossLibraryDirectory:=FParent.CrossLibraryDirectory;
      FInstaller.CrossToolsDirectory:=FParent.CrossToolsDirectory;
    end
    else
      FInstaller:=TFPCNativeInstaller.Create;
    FInstaller.SourceDirectory:=FParent.FPCSourceDirectory;
    FInstaller.InstallDirectory:=FParent.FPCInstallDirectory;
    (FInstaller as TFPCInstaller).BootstrapCompilerDirectory:=FParent.BootstrapCompilerDirectory;
    (FInstaller as TFPCInstaller).BootstrapCompilerURL:=FParent.BootstrapCompilerURL;
    (FInstaller as TFPCInstaller).SourcePatches:=FParent.FFPCPatches;
    FInstaller.Compiler:='';  //bootstrap used
    FInstaller.CompilerOptions:=FParent.FPCOPT;
    FInstaller.DesiredRevision:=FParent.FPCDesiredRevision;
    FInstaller.DesiredBranch:=FParent.FPCDesiredBranch;
    FInstaller.URL:=FParent.FPCURL;
    end

  {$ifndef FPCONLY}
  // Lazarus:
  else if (uppercase(ModuleName)='LAZARUS') or (uppercase(ModuleName)='LAZBUILD') or (uppercase(ModuleName)='LCL') or
    (uppercase(ModuleName)='USERIDE') then
    begin
    if assigned(FInstaller) then
      begin
      if (not crosscompiling and (FInstaller is TLazarusNativeInstaller)) or
        (crosscompiling and (FInstaller is TLazarusCrossInstaller)) then
        begin
        exit; //all fine, continue with current FInstaller
        end
      else
        FInstaller.free; // get rid of old FInstaller
      end;
    if CrossCompiling then
      begin
      FInstaller:=TLazarusCrossInstaller.Create;
      FInstaller.CrossCPU_Target:=FParent.CrossCPU_Target;
      FInstaller.CrossOPT:=FParent.CrossOPT;
      FInstaller.CrossOS_Target:=FParent.CrossOS_Target;
      FInstaller.CrossOS_SubArch:=FParent.CrossOS_SubArch;
      end
    else
      FInstaller:=TLazarusNativeInstaller.Create;
    // source- and install-dir are the same for Lazarus ... could be changed
    FInstaller.SourceDirectory:=FParent.LazarusDirectory ;
    FInstaller.InstallDirectory:=FParent.LazarusDirectory ;
    if FParent.CompilerName='' then
      FInstaller.Compiler:=FInstaller.GetCompilerInDir(FParent.FPCInstallDirectory)
    else
      FInstaller.Compiler:=FParent.CompilerName;
    FInstaller.CompilerOptions:=FParent.LazarusOPT;
    FInstaller.DesiredRevision:=FParent.LazarusDesiredRevision;
    FInstaller.DesiredBranch:=FParent.LazarusDesiredBranch;
    // CrossLCL_Platform is only used when building LCL, but the Lazarus module
    // will take care of that.
    (FInstaller as TLazarusInstaller).CrossLCL_Platform:=FParent.CrossLCL_Platform;
    (FInstaller as TLazarusInstaller).FPCSourceDir:=FParent.FPCSourceDirectory;
    (FInstaller as TLazarusInstaller).FPCInstallDir:=FParent.FPCInstallDirectory;
    (FInstaller as TLazarusInstaller).PrimaryConfigPath:=FParent.LazarusPrimaryConfigPath;
    (FInstaller as TLazarusInstaller).SourcePatches:=FParent.FLazarusPatches;
    FInstaller.URL:=FParent.LazarusURL;
    end

  //Convention: help modules start with HelpFPC
  //or HelpLazarus
  {$endif}
  else if uppercase(ModuleName)='HELPFPC' then
      begin
      if assigned(FInstaller) then
        begin
        if (FInstaller is THelpFPCInstaller) then
          begin
          exit; //all fine, continue with current FInstaller
          end
        else
          FInstaller.free; // get rid of old FInstaller
        end;
      FInstaller:=THelpFPCInstaller.Create;
      FInstaller.SourceDirectory:=FParent.FPCSourceDirectory;
      if FParent.CompilerName='' then
        FInstaller.Compiler:=FInstaller.GetCompilerInDir(FParent.FPCInstallDirectory)
      else
        FInstaller.Compiler:=FParent.CompilerName;
      end
  {$ifndef FPCONLY}
  else if uppercase(ModuleName)='HELPLAZARUS' then
      begin
      if assigned(FInstaller) then
        begin
       if (FInstaller is THelpLazarusInstaller) then
          begin
          exit; //all fine, continue with current FInstaller
          end
        else
          FInstaller.free; // get rid of old FInstaller
        end;
      FInstaller:=THelpLazarusInstaller.Create;
      FInstaller.SourceDirectory:=FParent.LazarusDirectory;
      // the same ... may change in the future
      FInstaller.InstallDirectory:=FParent.LazarusDirectory;
      if FParent.CompilerName='' then
        FInstaller.Compiler:=FInstaller.GetCompilerInDir(FParent.FPCInstallDirectory)
      else
        FInstaller.Compiler:=FParent.CompilerName;
      (FInstaller as THelpLazarusInstaller).FPCBinDirectory:=IncludeTrailingBackslash(FParent.FPCInstallDirectory);// + 'bin' + DirectorySeparator + FInstaller.SourceCPU + '-' + FInstaller.SourceOS;
      (FInstaller as THelpLazarusInstaller).FPCSourceDirectory:=FParent.FPCSourceDirectory;
      (FInstaller as THelpLazarusInstaller).LazarusPrimaryConfigPath:=FParent.LazarusPrimaryConfigPath;
      end
  {$endif}
  else       // this is a universal module
    begin
      if assigned(FInstaller) then
        begin
        if (FInstaller is TUniversalInstaller) and
          (FCurrentModule= ModuleName) then
          begin
          exit; //all fine, continue with current FInstaller
          end
        else
          FInstaller.free; // get rid of old FInstaller
        end;
      FInstaller:=TUniversalInstaller.Create;
      FCurrentModule:=ModuleName;
      //assign properties
      (FInstaller as TUniversalInstaller).FPCDir:=FParent.FPCInstallDirectory;
      // Use compileroptions for chosen FPC compile options...
      FInstaller.CompilerOptions:=FParent.FPCOPT;
      // ... but more importantly, pass Lazarus compiler options needed for IDE rebuild
      {$ifndef FPCONLY}
      (FInstaller as TUniversalInstaller).LazarusCompilerOptions:=FParent.FLazarusOPT;
      (FInstaller as TUniversalInstaller).LazarusDir:=FParent.FLazarusDirectory;
      (FInstaller as TUniversalInstaller).LazarusPrimaryConfigPath:=FParent.LazarusPrimaryConfigPath;
      {$endif}
      if FParent.CompilerName='' then
        FInstaller.Compiler:=FInstaller.GetCompilerInDir(FParent.FPCInstallDirectory)
      else
        FInstaller.Compiler:=FParent.CompilerName;
    end;


  if assigned(FInstaller) then
  begin
    FInstaller.BaseDirectory:=FParent.BaseDirectory;
    if Assigned(FInstaller.SVNClient) then
      FInstaller.SVNClient.RepoExecutable := FParent.SVNExecutable;
    FInstaller.HTTPProxyHost:=FParent.HTTPProxyHost;
    FInstaller.HTTPProxyPort:=FParent.HTTPProxyPort;
    FInstaller.HTTPProxyUser:=FParent.HTTPProxyUser;
    FInstaller.HTTPProxyPassword:=FParent.HTTPProxyPassword;
    FInstaller.KeepLocalChanges:=FParent.KeepLocalChanges;
    FInstaller.ReApplyLocalChanges:=FParent.ReApplyLocalChanges;
    FInstaller.PatchCmd:=FParent.PatchCmd;
    FInstaller.Verbose:=FParent.Verbose;
    FInstaller.UseWget:=FParent.UseWget;
    FInstaller.ExportOnly:=FParent.ExportOnly;
    FInstaller.NoJobs:=FParent.NoJobs;
    FInstaller.Log:=FParent.FLog;
    {$IFDEF MSWINDOWS}
    FInstaller.MakeDirectory:=FParent.MakeDirectory;
    {$ENDIF}
  end;
end;

function TSequencer.GetText: string;
var
  i:integer;
begin
  result:='';
  for i:=Low(FStateMachine) to High(FStateMachine) do
  begin
    // todo: add translation of instr
    result:=result+
      'Instruction number: '+inttostr(ord(FStateMachine[i].instr))+' '+
      FStateMachine[i].param;
    if i<High(FStateMachine) then
      result:=result+LineEnding;
  end;
end;

function TSequencer.IsSkipped(ModuleName: string): boolean;
begin
  try
    result:=assigned(FSkipList) and (FSkipList.IndexOf(Uppercase(ModuleName))>=0);
  except
    result:=false;
  end;
end;

procedure TSequencer.ResetAllExecuted(SkipFPC: boolean);
var
  idx:integer;
begin
  for idx:=0 to FParent.FModuleList.Count -1 do
    // convention: FPC sequences that are to be skipped start with 'FPC'. Used in SetLCL.
    // todo: skip also help???? Who would call several help installs in one sequence? SubSequences?
    if not SkipFPC or (pos('FPC',Uppercase(FParent.FModuleList[idx]))<>1) then
      PSequenceAttributes(FParent.FModuleList.Objects[idx])^.Executed:=ESNever;
end;

function TSequencer.AddSequence(Sequence: string): boolean;
//our mini parser
var
  line,key,param:string;
  i:integer;
  instr:TKeyword;
  sequencename:string='';

  function KeyStringToKeyword(Key:string):TKeyword;
  begin
    if key='DECLARE' then result:=SMdeclare
    else if key='DECLAREHIDDEN' then result:=SMdeclareHidden
    else if key='DO' then result:=SMdo
    else if key='REQUIRES' then result:=SMrequire
    else if key='EXEC' then result:=SMexec
    else if key='END' then result:=SMend
    else if key='CLEANMODULE' then result:=SMcleanmodule
    else if key='GETMODULE' then result:=SMgetmodule
    else if key='BUILDMODULE' then result:=SMbuildmodule
    else if key='UNINSTALLMODULE' then result:=SMuninstallmodule
    else if key='CONFIGMODULE' then result:=SMconfigmodule
    {$ifndef FPCONLY}
    else if key='RESETLCL' then result:=SMResetLCL
    {$endif}
    else if key='SETOS' then result:=SMSetOS
    else if key='SETCPU' then result:=SMSetCPU
    else result:=SMInvalid;
  end;

  //remove white space and line terminator
  function NoWhite(s:string):string;
  begin
    while (s[1]<=' ') or (s[1]=';') do delete(s,1,1);
    while (s[length(s)]<=' ') or (s[length(s)]=';') do delete(s,length(s),1);
    result:=s;
  end;

begin
while Sequence<>'' do
  begin
  i:=pos(';',Sequence);
  if i>0 then
    line:=copy(Sequence,1,i-1)
  else
    line:=Sequence;
  delete(Sequence,1,length(line)+1);
  line:=NoWhite(line);
  if line<>'' then
    begin
    i:=pos(' ',line);
    if i>0 then
      begin
      key:=copy(line,1,i-1);
      param:=NoWhite(copy(line,i,length(line)));
      end
    else
      begin
      key:=line;
      param:='';
      end;
    key:=NoWhite(key);
    if key<>'' then
      begin
      i:=Length(FStateMachine);
      SetLength(FStateMachine,i+1);
      instr:=KeyStringToKeyword(Uppercase(Key));
      FStateMachine[i].instr:=instr;
      if instr=SMInvalid then
        FParent.WritelnLog('Invalid instruction '+Key+' in sequence '+sequencename);
      FStateMachine[i].param:=param;
      if instr in [SMdeclare,SMdeclareHidden] then
        begin
        AddToModuleList(uppercase(param),i);
        sequencename:=param;
        end;
      if instr = SMdeclare then
        FParent.FModulePublishedList.Add(param);
      end;
    end;
  end;
result:=true;
end;


// create the sequence corresponding with the only parameters
function TSequencer.CreateOnly(OnlyModules: string): boolean;
var
  i:integer;
  seq:string;

begin
AddToModuleList('ONLY',Length(FStateMachine));
while Onlymodules<>'' do
  begin
  i:=pos(',',Onlymodules);
  if i>0 then
    seq:=copy(Onlymodules,1,i-1)
  else
    seq:=Onlymodules;
  delete(Onlymodules,1,length(seq)+1);
  // We could build a sequence string and have it parsed by AddSequence.
  // Pro: no dependency on FStateMachine structure
  // Con: dependency on sequence format; double parsing
  if seq<>'' then
    begin
    i:=Length(FStateMachine);
    SetLength(FStateMachine,i+1);
    FStateMachine[i].instr:=SMdo;
    FStateMachine[i].param:=seq;
    end;
  end;
i:=Length(FStateMachine);
SetLength(FStateMachine,i+1);
FStateMachine[i].instr:=SMend;
FStateMachine[i].param:='';
result:=true;
end;

function TSequencer.DeleteOnly: boolean;
var i,idx:integer;
  SeqAttr:^TSequenceAttributes;
begin
idx:=FParent.FModuleList.IndexOf('ONLY');
if (idx >0) then
  begin
  SeqAttr:=PSequenceAttributes(pointer(FParent.FModuleList.Objects[idx]));
  i:=SeqAttr^.EntryPoint;
  while i<length(FStateMachine) do
    begin
    FStateMachine[i].param:='';
    i:=i+1;
    end;
  SetLength(FStateMachine,SeqAttr^.EntryPoint);
  Freemem(FParent.FModuleList.Objects[idx]);
  FParent.FModuleList.Delete(idx);
  end;
result:=true;
end;

function TSequencer.Run(SequenceName: string): boolean;
var
  EntryPoint,InstructionPointer:integer;
  idx:integer;
  SeqAttr:^TSequenceAttributes;

  Procedure CleanUpInstaller;
  begin
    if assigned(FInstaller) then
      begin
      FInstaller.Free;
      FInstaller:=nil;
      end;
  end;

begin
  if not assigned(FParent.FModuleList) then
    begin
    result:=false;
    FParent.WritelnLog('Error: No sequences loaded while trying to find sequence name ' + SequenceName);
    exit;
    end;
  // --clean or --install ??
  if FParent.Uninstall then  // uninstall overrides clean
    begin
    if (UpperCase(SequenceName)<>'ONLY') and (uppercase(copy(SequenceName,length(SequenceName)-8,9))<>'UNINSTALL') then
      SequenceName:=SequenceName+'uninstall';
    end
  else if FParent.Clean  then
    begin
    if (UpperCase(SequenceName)<>'ONLY') and (uppercase(copy(SequenceName,length(SequenceName)-4,5))<>'CLEAN') then
      SequenceName:=SequenceName+'clean';
    end;
  // find sequence
  idx:=FParent.FModuleList.IndexOf(Uppercase(SequenceName));
  if (idx>=0) then
    begin
    result:=true;
    SeqAttr:=PSequenceAttributes(pointer(FParent.FModuleList.Objects[idx]));
    // Don't run sequence if already run
    case SeqAttr^.Executed of
      ESFailed : begin
        infoln('State machine: already ran sequence name '+SequenceName+' ending in failure. Not running again.',etWarning);
        result:=false;
        exit;
        end;
      ESSucceeded : begin
        infoln('State machine: already succesfully ran sequence name '+SequenceName+'. Not running again.',etInfo);
        exit;
        end;
      end;
    // Get entry point in FStateMachine
    InstructionPointer:=SeqAttr^.EntryPoint;
    EntryPoint:=InstructionPointer;
    // run sequence until end or failure
    while true do
      begin
      { For debugging state machine sequence:
      FParent.writelnlog('State machine: ',true);
      FParent.writelnlog(FStateMachine[InstructionPointer].instr,true);
      FParent.writelnlog(FStateMachine[InstructionPointer].param,true);
      }
      case FStateMachine[InstructionPointer].instr of
        SMdeclare     :;
        SMdeclareHidden :;
        SMdo          : if not IsSkipped(FStateMachine[InstructionPointer].param) then
                          result:=Run(FStateMachine[InstructionPointer].param);
        SMrequire     : result:=Run(FStateMachine[InstructionPointer].param);
        SMexec        : result:=DoExec(FStateMachine[InstructionPointer].param);
        SMend         : begin
                          SeqAttr^.Executed:=ESSucceeded;
                          CleanUpInstaller;
                          exit; //success
                        end;
        SMcleanmodule : result:=DoCleanModule(FStateMachine[InstructionPointer].param);
        SMgetmodule   : result:=DoGetModule(FStateMachine[InstructionPointer].param);
        SMbuildmodule : result:=DoBuildModule(FStateMachine[InstructionPointer].param);
        SMuninstallmodule: result:=DoUnInstallModule(FStateMachine[InstructionPointer].param);
        SMconfigmodule: result:=DoConfigModule(FStateMachine[InstructionPointer].param);
        {$ifndef FPCONLY}
        SMResetLCL    : DoResetLCL;
        {$endif}
        SMSetOS       : DoSetOS(FStateMachine[InstructionPointer].param);
        SMSetCPU      : DoSetCPU(FStateMachine[InstructionPointer].param);
        end;
      if not result then
        begin
        SeqAttr^.Executed:=ESFailed;
        FParent.WritelnLog('Error running fpcup. Technical details: error executing sequence '+SequenceName+
          '; line: '+IntTostr(InstructionPointer - EntryPoint+1)+
          ', param: '+FStateMachine[InstructionPointer].param);
        CleanUpInstaller;
        exit; //failure, bail out
        end;
      InstructionPointer:=InstructionPointer+1;
      if InstructionPointer>=length(FStateMachine) then  //somebody forgot end
        begin
        SeqAttr^.Executed:=ESSucceeded;
        CleanUpInstaller;
        exit; //success
        end;
      end;
    end
  else
    begin
    result:=false;  // sequence not found
    FParent.WritelnLog('Error: Failed to load sequence :' + SequenceName);
    end;
end;

constructor TSequencer.Create;
begin

end;

destructor TSequencer.Destroy;
begin
  inherited Destroy;
end;

end.


unit m_crossdarwin32iphonesim;

{ Cross compiles from Darwin to Darwin 32 bit iphone simulator
}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, m_crossinstaller, fpcuputil;

implementation
const
  ErrorNotFound='An error occurred getting cross compiling binutils/libraries.'+LineEnding+
    'todo: specify what exactly is missing';

type

{ TDarwin32iphonesim }

TDarwin32iphonesim = class(TCrossInstaller)
private
  FAlreadyWarned: boolean; //did we warn user about errors and fixes already?
public
  function GetLibs(Basepath:string):boolean;override;
  function GetBinUtils(Basepath:string):boolean;override;
  constructor Create;
  destructor Destroy; override;
end;

{ TDarwin32iphonesim }

function TDarwin32iphonesim.GetLibs(Basepath:string): boolean;
var
  IOS_BASE:string;
begin
  result:=FLibsFound;
  if result then exit;

  FLibsPath:='';
  result:=true;
  FLibsFound:=true;

  IOS_BASE:='/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk';
  if NOT DirectoryExists(IOS_BASE) then
     IOS_BASE:='/Volumes/Xcode/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk';

  if DirectoryExists(IOS_BASE) then
  begin
    FLibsPath:=IncludeTrailingPathDelimiter(IOS_BASE)+'usr/lib/';
    //FFPCCFGSnippet:=FFPCCFGSnippet+LineEnding+
    //'-XR'+ExcludeTrailingPathDelimiter(IOS_BASE);
    //'-Xr'+IncludeTrailingPathDelimiter(FLibsPath); //set linker's rlink path
    //'-Xr'+IncludeTrailingPathDelimiter(IOS_BASE); //set linker's rlink path
    //'-Xr'; //set linker's rlink path
  end;

end;

function TDarwin32iphonesim.GetBinUtils(Basepath:string): boolean;
var
  IOS_BASE:string;
begin
  result:=inherited;
  if result then exit;

  FBinUtilsPath:='';
  FBinUtilsPrefix:=''; // we have the "native" names, no prefix
  result:=true;
  FBinsFound:=true;

  IOS_BASE:='/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk';
  if NOT DirectoryExists(IOS_BASE) then
     IOS_BASE:='/Volumes/Xcode/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk';

  if DirectoryExists(IOS_BASE) then
  begin
    FBinUtilsPath:=IncludeTrailingPathDelimiter(IOS_BASE)+'usr/bin';
    FFPCCFGSnippet:=FFPCCFGSnippet+LineEnding+
    '-FD'+FBinUtilsPath+LineEnding+ {search this directory for compiler utilities}
    '-XR'+ExcludeTrailingPathDelimiter(IOS_BASE);
  end;
end;

constructor TDarwin32iphonesim.Create;
begin
  inherited Create;
  FCrossModuleName:='Darwin32iphonesim';
  FTargetCPU:='i386';
  FTargetOS:='iphonesim';
  FAlreadyWarned:=false;
  FFPCCFGSnippet:=''; //no need to change fpc.cfg
  infoln('TDarwin32iphonesim crosscompiler loading',etDebug);
end;

destructor TDarwin32iphonesim.Destroy;
begin
  inherited Destroy;
end;

{$IFDEF Darwin}
var
  Darwin32iphonesim:TDarwin32iphonesim;

initialization
  Darwin32iphonesim:=TDarwin32iphonesim.Create;
  RegisterExtension(Darwin32iphonesim.TargetCPU+'-'+Darwin32iphonesim.TargetOS,Darwin32iphonesim);
finalization
  Darwin32iphonesim.Destroy;
{$ENDIF}
end.


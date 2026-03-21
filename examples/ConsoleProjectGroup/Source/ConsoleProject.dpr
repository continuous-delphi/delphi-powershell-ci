program ConsoleProject;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  ConsoleProject.AppMain in 'ConsoleProject.AppMain.pas',
  ConsoleProject.AppExitCodes in 'ConsoleProject.AppExitCodes.pas';

begin

  TAppMain.Run;

end.

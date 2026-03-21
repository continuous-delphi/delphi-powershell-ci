unit ConsoleProject.AppMain;

interface

type

  TAppMain = record
    class procedure EmitTextError(const AMsg: string); static;

    class function Run: Integer; static;
  end;

implementation

uses
  System.SysUtils,
  ConsoleProject.AppExitCodes;


class procedure TAppMain.EmitTextError(const AMsg: string);
begin
  WriteLn(System.ErrOutput, AMsg);
end;


class function TAppMain.Run: Integer;
begin

  try

    {PROJECT_TEMPLATE_TODO}

    Result := TAppExitCodes.ExitSuccess;
  except
    on E: Exception do
    begin
      EmitTextError(E.Message);
      Result := TAppExitCodes.ExitUnexpectedError;
    end;
  end;
end;

end.

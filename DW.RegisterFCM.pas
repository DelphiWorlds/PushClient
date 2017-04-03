unit DW.RegisterFCM;

(*
  DelphiWorlds PushClient project
  ------------------------------------------
  A cross-platform method of using Firebase Cloud Messaging (FCM) to receive push notifications

  This project was inspired by the following article:
    http://thundaxsoftware.blogspot.co.id/2017/01/firebase-cloud-messaging-with-delphi.html
*)

{$I DW.GlobalDefines.inc}

interface

uses
  // RTL
  System.Classes;

type
  TFCMRequestCompleteEvent = procedure (Sender: TObject; const Success: Boolean; const RequestResult: string) of object;

  TRegisterFCM = class(TObject)
  private
    FOnRequestComplete: TFCMRequestCompleteEvent;
    procedure DoParseResult(const AContent: string);
    procedure DoRequestComplete(const ASuccess: Boolean; const ARequestResult: string);
    procedure DoRegister(const AServerKey: string; const ARequest: TStream);
    procedure DoRegisterAPNToken(const AServerKey, ARequest: string);
  public
    /// <summary>
    ///   Sends a request to Google APIs to convert an APNs token to an FCM token
    /// </summary>
    /// <remarks>
    ///   AAppBundleID should match the bundle id for the app specified on FCM
    ///   AServerKey is the server key specified on FCM
    ///   AToken is the iOS device token returned when starting the APS push service
    /// </remarks>
    procedure RegisterAPNToken(const AAppBundleID, AServerKey, AToken: string; const ASandbox: Boolean = False);
    property OnRequestComplete: TFCMRequestCompleteEvent read FOnRequestComplete write FOnRequestComplete;
  end;

implementation

uses
  // RTL
  System.SysUtils, System.Net.HttpClient, System.Net.URLClient, System.NetConsts, System.JSON, System.Threading,
  // REST
  REST.Types;

const
  cSandboxValues: array[Boolean] of string = ('false', 'true');
  cHTTPResultOK = 200;
  cFCMIIDBatchImportURL = 'https://iid.googleapis.com/iid/v1:batchImport';
  cFCMAuthorizationHeader = 'Authorization';
  cFCMAuthorizationHeaderValuePair = 'key=%s';
  cResultsValueName = 'results';
  cStatusValueName = 'status';
  cRegistrationTokenValueName = 'registration_token';
  cStatusValueOK = 'OK';
  cFCMResultError = 'FCM Result Error: %s';
  cFCMJSONError = 'FCM Unexpected JSON: %s';
  cHTTPError = 'HTTP Error: %s. Response: %s';
  cFCMRequestJSONTemplate = '{ "application": "%s", "sandbox": %s, "apns_tokens": [ "%s" ] }';

{ TRegisterFCM }

procedure TRegisterFCM.DoRequestComplete(const ASuccess: Boolean; const ARequestResult: string);
begin
  if Assigned(FOnRequestComplete) then
  begin
    TThread.Synchronize(nil,
      procedure
      begin
        FOnRequestComplete(Self, ASuccess, ARequestResult);
      end
    );
  end;
end;

procedure TRegisterFCM.DoParseResult(const AContent: string);
var
  LResponse: TJSONValue;
  LResult: TJSONObject;
  LResults: TJSONArray;
  LToken, LStatus: string;
  LIsParseOK: Boolean;
begin
  LIsParseOK := False;
  LResponse := TJSONObject.ParseJSONValue(AContent);
  if (LResponse <> nil) and LResponse.TryGetValue<TJSONArray>(cResultsValueName, LResults) then
  try
    if (LResults.Count > 0) and (LResults.Items[0] is TJSONObject) then
    begin
      LResult := TJSONObject(LResults.Items[0]);
      LResult.TryGetValue<string>(cRegistrationTokenValueName, LToken);
      LResult.TryGetValue<string>(cStatusValueName, LStatus);
      if not LStatus.IsEmpty then
      begin
        LIsParseOK := True;
        if not LStatus.Equals(cStatusValueOK) then
          DoRequestComplete(False, Format(cFCMResultError, [LStatus]))
        else if not LToken.IsEmpty then
          DoRequestComplete(True, LToken) // Status of OK, token present
        else
          LIsParseOK := False; // Status of OK, but token missing
      end;
    end;
  finally
    LResponse.Free;
  end;
  if not LIsParseOK then
    DoRequestComplete(False, Format(cFCMJSONError, [AContent]));
end;

procedure TRegisterFCM.DoRegister(const AServerKey: string; const ARequest: TStream);
var
  LHTTP: THTTPClient;
  LResponse: IHTTPResponse;
begin
  // Use the native HTTP client to send the request
  LHTTP := THTTPClient.Create;
  try
    LHTTP.CustomHeaders[cFCMAuthorizationHeader] := Format(cFCMAuthorizationHeaderValuePair, [AServerKey]);
    LHTTP.ContentType := CONTENTTYPE_APPLICATION_JSON;
    LResponse := LHTTP.Post(cFCMIIDBatchImportURL, ARequest);
    if LResponse.StatusCode = cHTTPResultOK then
      DoParseResult(LResponse.ContentAsString)
    else
      DoRequestComplete(False, Format(cHTTPError, [LResponse.StatusText, LResponse.ContentAsString]));
  finally
    LHTTP.Free;
  end;
end;


procedure TRegisterFCM.DoRegisterAPNToken(const AServerKey, ARequest: string);
var
  LStream: TStream;
begin
  LStream := TStringStream.Create(ARequest);
  try
    DoRegister(AServerKey, LStream);
  finally
    LStream.Free;
  end;
end;

procedure TRegisterFCM.RegisterAPNToken(const AAppBundleID, AServerKey, AToken: string; const ASandbox: Boolean = False);
begin
  // Do the request asynch via TTask
  TTask.Run(
    procedure
    begin
      DoRegisterAPNToken(AServerKey, Format(cFCMRequestJSONTemplate, [AAppBundleID, cSandboxValues[ASandbox], AToken]));
    end
  );
end;

end.

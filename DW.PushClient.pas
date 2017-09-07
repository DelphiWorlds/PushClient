unit DW.PushClient;

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
  System.PushNotification,
  // DW
  DW.RegisterFCM;

type
  TPushSystem = (APS, GCM);

  TRegistrationErrorEvent = procedure(Sender: TObject; const Error: string) of object;

  TPushClient = class(TObject)
  private
    FBundleID: string;
    FDeviceID: string;
    FDeviceToken: string;
    FPushService: TPushService;
    FPushSystem: TPushSystem;
    FRegisterFCM: TRegisterFCM;
    FServerKey: string;
    FServiceConnection: TPushServiceConnection;
    FUseSandbox: Boolean;
    FOnChange: TPushServiceConnection.TChangeEvent;
    FOnReceiveNotification: TPushServiceConnection.TReceiveNotificationEvent;
    FOnRegistrationError: TRegistrationErrorEvent;
    procedure ActivateAsync;
    procedure ClearDeviceInfo;
    procedure CreatePushService;
    procedure DoChange(AChange: TPushService.TChanges);
    procedure DoRegistrationError(const AError: string);
    function GetActive: Boolean;
    function GetGCMAppID: string;
    procedure ServiceConnectionChangeHandler(Sender: TObject; AChange: TPushService.TChanges);
    procedure ServiceConnectionReceiveNotificationHandler(Sender: TObject; const ANotification: TPushServiceNotification);
    procedure SetActive(const Value: Boolean);
    procedure SetGCMAppID(const Value: string);
    procedure RegisterFCMRequestCompleteHandler(Sender: TObject; const Success: Boolean; const RequestResult: string);
  public
    constructor Create;
    destructor Destroy; override;
    property Active: Boolean read GetActive write SetActive;
    property BundleID: string read FBundleID write FBundleID;
    property DeviceID: string read FDeviceID;
    property DeviceToken: string read FDeviceToken;
    property GCMAppID: string read GetGCMAppID write SetGCMAppID;
    property PushSystem: TPushSystem read FPushSystem;
    property UseSandbox: Boolean read FUseSandbox write FUseSandbox;
    property ServerKey: string read FServerKey write FServerKey;
    property OnChange: TPushServiceConnection.TChangeEvent read FOnChange write FOnChange;
    property OnReceiveNotification: TPushServiceConnection.TReceiveNotificationEvent read FOnReceiveNotification write FOnReceiveNotification;
    property OnRegistrationError: TRegistrationErrorEvent read FOnRegistrationError write FOnRegistrationError;
  end;

implementation

uses
  // RTL
  System.SysUtils, System.Threading, System.Classes,
  // FMX
{$IF Defined(IOS)}
  FMX.PushNotification.iOS;
{$ENDIF}
{$IF Defined(Android)}
  FMX.PushNotification.Android;
{$ENDIF}

{ TPushClient }

constructor TPushClient.Create;
begin
  inherited;
  CreatePushService;
end;

destructor TPushClient.Destroy;
begin
  FServiceConnection.Free;
  FPushService.Free;
  FRegisterFCM.Free;
  inherited;
end;

procedure TPushClient.CreatePushService;
begin
  case TOSVersion.Platform of
    TOSVersion.TPlatform.pfiOS:
    begin
      FPushSystem := TPushSystem.APS;
      FPushService := TPushServiceManager.Instance.GetServiceByName(TPushService.TServiceNames.APS);
      // FCM for iOS requires that the APNs token be "converted" to an FCM token. This is what TRegisterFCM does
      FRegisterFCM := TRegisterFCM.Create;
      FRegisterFCM.OnRequestComplete := RegisterFCMRequestCompleteHandler;
    end;
    TOSVersion.TPlatform.pfAndroid:
    begin
      FPushSystem := TPushSystem.GCM;
      FPushService := TPushServiceManager.Instance.GetServiceByName(TPushService.TServiceNames.GCM);
    end;
  else
    raise Exception.Create('Unsupported platform');
  end;
  FServiceConnection := TPushServiceConnection.Create(FPushService);
  FServiceConnection.OnChange := ServiceConnectionChangeHandler;
  FServiceConnection.OnReceiveNotification := ServiceConnectionReceiveNotificationHandler;
end;

procedure TPushClient.DoChange(AChange: TPushService.TChanges);
begin
  if FServiceConnection.Active then
    FDeviceID := FPushService.DeviceIDValue[TPushService.TDeviceIDNames.DeviceID];
  if Assigned(FOnChange) then
    TThread.Synchronize(nil,
      procedure
      begin
        FOnChange(Self, AChange);
      end
    );
end;

procedure TPushClient.DoRegistrationError(const AError: string);
begin
  if Assigned(FOnRegistrationError) then
    FOnRegistrationError(Self, AError);
end;

function TPushClient.GetActive: Boolean;
begin
  Result := FServiceConnection.Active;
end;

function TPushClient.GetGCMAppID: string;
begin
  Result := FPushService.AppProps[TPushService.TAppPropNames.GCMAppID];
end;

procedure TPushClient.RegisterFCMRequestCompleteHandler(Sender: TObject; const Success: Boolean; const RequestResult: string);
begin
  // FCM token registration has completed
  if Success then
  begin
    FDeviceToken := RequestResult;
    DoChange([TPushService.TChange.DeviceToken]);
  end
  else
    DoRegistrationError(RequestResult);
end;

procedure TPushClient.ServiceConnectionChangeHandler(Sender: TObject; AChange: TPushService.TChanges);
var
  LTokenChange: Boolean;
  LDeviceToken: string;
begin
  LTokenChange := TPushService.TChange.DeviceToken in AChange;
  if LTokenChange then
  begin
    LDeviceToken := FPushService.DeviceTokenValue[TPushService.TDeviceTokenNames.DeviceToken];
    // If the token needs registration with FCM, FRegisterFCM will be non-nil
    if FRegisterFCM <> nil then
      FRegisterFCM.RegisterAPNToken(FBundleID, FServerKey, LDeviceToken, FUseSandbox)
    else
      FDeviceToken := LDeviceToken;
  end;
  // If it's not a token change, or registration is not required, call DoChange immediately
  if not LTokenChange or (FRegisterFCM = nil) then
    DoChange(AChange);
end;

procedure TPushClient.ServiceConnectionReceiveNotificationHandler(Sender: TObject; const ANotification: TPushServiceNotification);
begin
  if Assigned(FOnReceiveNotification) then
    FOnReceiveNotification(Self, ANotification);
end;

procedure TPushClient.SetActive(const Value: Boolean);
begin
  if Value = FServiceConnection.Active then
    Exit; // <=======
  if Value then
    ActivateAsync
  else
    ClearDeviceInfo;
end;

procedure TPushClient.ActivateAsync;
begin
  TTask.Run(
    procedure
    begin
      FServiceConnection.Active := True;
    end
  );
end;

procedure TPushClient.SetGCMAppID(const Value: string);
begin
  FPushService.AppProps[TPushService.TAppPropNames.GCMAppID] := Value;
end;

procedure TPushClient.ClearDeviceInfo;
begin
  FDeviceID := '';
  FDeviceToken := '';
end;

end.

unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.PushNotification,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo,
  DW.PushClient;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
  private
    FPushClient: TPushClient;
    procedure PushClientChangeHandler(Sender: TObject; AChange: TPushService.TChanges);
    procedure PushClientReceiveNotificationHandler(Sender: TObject; const ANotification: TPushServiceNotification);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

uses
  // Create the unit FCMConsts and declare consts for:
  //  cFCMServerKey
  //  cFCMSenderID
  //  cFCMBundleID
  //    These values are at a URL similar to: https://console.firebase.google.com/project/myproject-xxxxxx/settings/cloudmessaging
  //    Where: myproject-xxxxxx is your project identifier on FCM. Go to: https://console.firebase.google.com and log in to check
  FCMConsts;

{ TForm1 }

constructor TForm1.Create(AOwner: TComponent);
begin
  inherited;
  FPushClient := TPushClient.Create;
  FPushClient.GCMAppID := cFCMSenderID;
  FPushClient.ServerKey := cFCMServerKey;
  FPushClient.BundleID := cFCMBundleID;
  FPushClient.UseSandbox := True; // Change this to False for production use!
  FPushClient.OnChange := PushClientChangeHandler;
  FPushClient.OnReceiveNotification := PushClientReceiveNotificationHandler;
  FPushClient.Active := True;
end;

destructor TForm1.Destroy;
begin
  FPushClient.Free;
  inherited;
end;

procedure TForm1.PushClientChangeHandler(Sender: TObject; AChange: TPushService.TChanges);
begin
  if TPushService.TChange.DeviceToken in AChange then
  begin
    Memo1.Lines.Add('DeviceID = ' + FPushClient.DeviceID);
    Memo1.Lines.Add('DeviceToken = ' + FPushClient.DeviceToken);
  end;
end;

procedure TForm1.PushClientReceiveNotificationHandler(Sender: TObject; const ANotification: TPushServiceNotification);
begin
  Memo1.Lines.Add('Notification: ' + ANotification.DataObject.ToString);
end;

end.

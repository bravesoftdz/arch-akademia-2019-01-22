﻿unit Form.Main;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.JSON,
  Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls,
  ChromeTabs, ChromeTabsClasses, ChromeTabsTypes,
  Utils.General,
  Messaging.EventBus,
  ExtGUI.ListBox.Books,
  Action.ImportFromWebService,
  Plus.TWork;

type
  TForm1 = class(TForm)
    GroupBox1: TGroupBox;
    lbBooksReaded: TLabel;
    Splitter1: TSplitter;
    lbBooksAvaliable: TLabel;
    lbxBooksReaded: TListBox;
    lbxBooksAvaliable2: TListBox;
    ChromeTabs1: TChromeTabs;
    pnMain: TPanel;
    btnImport: TButton;
    tmrAppReady: TTimer;
    Splitter2: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ChromeTabs1ButtonCloseTabClick(Sender: TObject; ATab: TChromeTab;
      var Close: Boolean);
    procedure ChromeTabs1Change(Sender: TObject; ATab: TChromeTab;
      TabChangeType: TTabChangeType);
    procedure FormResize(Sender: TObject);
    procedure Splitter1Moved(Sender: TObject);
    procedure tmrAppReadyTimer(Sender: TObject);
  private
    FBooksConfig: TBooksListBoxConfigurator;
    actImportFromWebService: TWorkAction;
    procedure OnImportReaderReportLog(MessageID: integer;
      const AMessagee: TEventMessage);
    procedure ResizeBooksListBoxesInsideGroupBox(aGroupBox: TGroupBox);
    function AddChromeTabAndCreateFrame(AFrameClass: TFrameClass;
      ACaption: string): TFrame;
    procedure OnWorkFDone(Sender: TObject; Work: TWork);
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  System.StrUtils, System.Math, System.DateUtils,
  Data.DB,
  Vcl.DBGrids, Vcl.Graphics,
  // TODO 2: [!] FireDAC dependency (requred because of FDManager) (comments below)
  // Should be moved into the DataModule
  FireDAC.Comp.Client,
  // TODO 2: [!] FireDAC dependency (requred because of EFDDBEngineException)
  FireDAC.Stan.Error,
  // ------------------------------------------------------------
  Consts.Application,
  Utils.CipherAES128,
  Data.Main,
  ClientAPI.Readers,
  ClientAPI.Books,
  Frame.Welcome,
  Frame.Import,
  Helper.DataSet,
  Helper.TDBGrid,
  Helper.TApplication,
  Helper.TWinControl,
  Helper.TJSONObject, Work.ImportBooks, Work.ImportReadReports;

var
  ShowBooksGrid: Boolean = False;

procedure TForm1.FormCreate(Sender: TObject);
var
  w1: TWork;
  w2: TWork;
begin
  pnMain.Caption := '';
  TEventBus._Register(EB_ImportReaderReports_LogInfo, OnImportReaderReportLog);

  FBooksConfig := TBooksListBoxConfigurator.Create(Self);

  actImportFromWebService := TWorkAction.Create(Self);
  actImportFromWebService.Caption := 'Import';
  btnImport.Action := actImportFromWebService;

  w1 := actImportFromWebService.CreateAndAddWork(TImportBooksWork);
  w2 := actImportFromWebService.CreateAndAddWork(TImportReadReportsWork);
  (w1 as TImportBooksWork).BooksConfig := FBooksConfig;
  (w2 as TImportReadReportsWork).BooksConfig := FBooksConfig;
  actImportFromWebService.OnWorkDone := OnWorkFDone;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TEventBus._Unregister(EB_ImportReaderReports_LogInfo,
    OnImportReaderReportLog);
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  ResizeBooksListBoxesInsideGroupBox(GroupBox1);
end;

procedure TForm1.OnImportReaderReportLog(MessageID: integer;
  const AMessagee: TEventMessage);
begin
  Caption := AMessagee.TagString;
end;

procedure TForm1.OnWorkFDone(Sender: TObject; Work: TWork);
var
  frm: TFrameImport;
  DataSrc1: TDataSource;
  DBGrid1: TDBGrid;
  DataSrc2: TDataSource;
  DBGrid2: TDBGrid;
begin
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  frm := AddChromeTabAndCreateFrame(TFrameImport, 'Readers') as TFrameImport;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Dynamically Add TDBGrid to TFrameImport
  //
  { TODO 2: [C] Move code down separate bussines logic from GUI }
  // warning for dataset dependencies, discuss TDBGrid dependencies
  DataSrc1 := TDataSource.Create(frm);
  DBGrid1 := TDBGrid.Create(frm);
  DBGrid1.AlignWithMargins := True;
  DBGrid1.Parent := frm;
  DBGrid1.Align := alClient;
  DBGrid1.DataSource := DataSrc1;
  DataSrc1.DataSet := DataModMain.dsReaders;
  // AutoSizeColumns(DBGrid1);
  DBGrid1.AutoSizeColumns();
  // ----------------------------------------------------------
  with TSplitter.Create(frm) do
  begin
    Align := alBottom;
    Parent := frm;
    Height := 5;
  end;
  DBGrid1.Margins.Bottom := 0;
  DataSrc2 := TDataSource.Create(frm);
  DBGrid2 := TDBGrid.Create(frm);
  DBGrid2.AlignWithMargins := True;
  DBGrid2.Parent := frm;
  DBGrid2.Align := alBottom;
  DBGrid2.Height := frm.Height div 3;
  DBGrid2.DataSource := DataSrc2;
  DataSrc2.DataSet := DataModMain.dsReports;
  DBGrid2.Margins.Top := 0;
  // AutoSizeColumns(DBGrid2);
  DBGrid2.AutoSizeColumns();
end;

procedure TForm1.ChromeTabs1ButtonCloseTabClick(Sender: TObject;
  ATab: TChromeTab; var Close: Boolean);
var
  obj: TObject;
begin
  obj := TObject(ATab.Data);
  (obj as TFrame).Free;
end;

procedure TForm1.ChromeTabs1Change(Sender: TObject; ATab: TChromeTab;
  TabChangeType: TTabChangeType);
var
  obj: TObject;
begin
  if Assigned(ATab) then
  begin
    obj := TObject(ATab.Data);
    if (TabChangeType = tcActivated) and Assigned(obj) then
    begin
      pnMain.HideAllChildFrames;
      (obj as TFrame).Visible := True;
    end;
  end;
end;

procedure TForm1.ResizeBooksListBoxesInsideGroupBox(aGroupBox: TGroupBox);
begin
  lbxBooksReaded.Height :=
    (lbxBooksReaded.Height + lbxBooksAvaliable2.Height) div 2;
end;

// TODO 99: Usunąć z klasy TForm1 (Form.Main.pas)
function TForm1.AddChromeTabAndCreateFrame(AFrameClass: TFrameClass;
  ACaption: string): TFrame;
var
  tab: TChromeTab;
begin
  Result := AFrameClass.Create(pnMain);
  Result.Parent := pnMain;
  Result.Visible := True;
  Result.Align := alClient;
  tab := ChromeTabs1.Tabs.Add;
  tab.Caption := ACaption;
  tab.Data := Result;
end;

procedure TForm1.Splitter1Moved(Sender: TObject);
begin
  (Sender as TSplitter).Tag := 1;
end;

procedure TForm1.tmrAppReadyTimer(Sender: TObject);
var
  frm: TFrameWelcome;
  datasrc: TDataSource;
  DataGrid: TDBGrid;
begin
  tmrAppReady.Enabled := False;
  if Application.IsDeveloperMode then
    ReportMemoryLeaksOnShutdown := True;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  frm := AddChromeTabAndCreateFrame(TFrameWelcome, 'Welcome') as TFrameWelcome;
  // ----------------------------------------------------------

  DataModMain.VerifyAndConnectToDatabase;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // * Initialize ListBox'es for books
  // * Load books form database
  // * Setup drag&drop functionality for two list boxes
  // * Setup OwnerDraw mode
  //
  FBooksConfig.PrepareListBoxes(lbxBooksReaded, lbxBooksAvaliable2);
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Create Books Grid for Quality Tests
  if Application.IsDeveloperMode and ShowBooksGrid then
  begin
    datasrc := TDataSource.Create(frm);
    DataGrid := TDBGrid.Create(frm);
    DataGrid.AlignWithMargins := True;
    DataGrid.Parent := frm;
    DataGrid.Align := alClient;
    DataGrid.DataSource := datasrc;
    datasrc.DataSet := DataModMain.dsBooks;
    // AutoSizeColumns(DataGrid);
    DataGrid.AutoSizeColumns();
  end;
end;

end.

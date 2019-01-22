﻿unit Form.Main;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes, System.JSON,
  Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls,
  ChromeTabs, ChromeTabsClasses, ChromeTabsTypes,
  ExtGUI.ListBox.Books;

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
    procedure btnImportClick(Sender: TObject);
    procedure ChromeTabs1ButtonCloseTabClick(Sender: TObject; ATab: TChromeTab;
      var Close: Boolean);
    procedure ChromeTabs1Change(Sender: TObject; ATab: TChromeTab;
      TabChangeType: TTabChangeType);
    procedure FormResize(Sender: TObject);
    procedure Splitter1Moved(Sender: TObject);
    procedure tmrAppReadyTimer(Sender: TObject);
  private
    FBooksConfig: TBooksListBoxConfigurator;
    FInDeveloperMode: Boolean;
    procedure ResizeBooksListBoxesInsideGroupBox(aGroupBox: TGroupBox);
    // TODO 4: Move this procedure into class (idea)
    procedure ValidateBookAndGetDateReported(jsRow: TJSONObject; email: string;
      var dtReported: TDateTime);
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  System.StrUtils, System.Math, System.DateUtils, System.RegularExpressions,
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
  Utils.General,
  Data.Main,
  ClientAPI.Readers,
  ClientAPI.Books,
  Frame.Welcome,
  Frame.Import;

const
  SecureKey = 'delphi-is-the-best';
  // SecurePassword = AES 128 ('masterkey',SecureKey)
  // SecurePassword = 'hC52IiCv4zYQY2PKLlSvBaOXc14X41Mc1rcVS6kyr3M=';
  // SecurePassword = AES 128 ('<null>',SecureKey)
  SecurePassword = 'EvUlRZOo3hzFEr/IRpHVMA==';
  Client_API_Token = '20be805d-9cea27e2-a588efc5-1fceb84d-9fb4b67c';
  SQL_GetDatabaseVersion = 'SELECT versionnr FROM DBInfo';

var
  ShowBooksGrid: Boolean = False;

resourcestring
  SWelcomeScreen = 'Welcome screen';
  SDBServerGone = 'Database server is gone';
  SDBConnectionUserPwdInvalid = 'Invalid database configuration.' +
    ' Application database user or password is incorrect.';
  SDBConnectionError = 'Can''t connect to database server. Unknown error.';
  SDBRequireCreate = 'Database is empty. You need to execute script' +
    ' creating required data.';
  SDBErrorSelect = 'Can''t execute SELECT command on the database';
  StrNotSupportedDBVersion = 'Not supported database version. Please' +
    ' update database structures.';

function DBVersionToString(VerDB: Integer): string;
begin
  Result := (VerDB div 1000).ToString + '.' + (VerDB mod 1000).ToString;
end;

procedure TForm1.FormResize(Sender: TObject);
begin
  ResizeBooksListBoxesInsideGroupBox(GroupBox1);
end;

{ TODO 1: [Helper] TWinControl class helper }
function SumHeightForChildrens(Parent: TWinControl;
  ControlsToExclude: TArray<TControl>): Integer;
var
  i: Integer;
  ctrl: Vcl.Controls.TControl;
  isExcluded: Boolean;
  j: Integer;
  sumHeight: Integer;
  ctrlHeight: Integer;
begin
  sumHeight := 0;
  for i := 0 to Parent.ControlCount - 1 do
  begin
    ctrl := Parent.Controls[i];
    isExcluded := False;
    for j := 0 to Length(ControlsToExclude) - 1 do
      if ControlsToExclude[j] = ctrl then
        isExcluded := True;
    if not isExcluded then
    begin
      if ctrl.AlignWithMargins then
        ctrlHeight := ctrl.Height + ctrl.Margins.Top + ctrl.Margins.Bottom
      else
        ctrlHeight := ctrl.Height;
      sumHeight := sumHeight + ctrlHeight;
    end;
  end;
  Result := sumHeight;
end;

{ TODO 1: [Helper] Extract into TDBGrid.ForEachRow class helper }
function AutoSizeColumns(DBGrid: TDBGrid; const MaxRows: Integer = 25): Integer;
var
  DataSet: Data.DB.TDataSet;
  Bookmark: TBookmark;
  Count, i: Integer;
  ColumnsWidth: array of Integer;
begin
  SetLength(ColumnsWidth, DBGrid.Columns.Count);
  for i := 0 to DBGrid.Columns.Count - 1 do
    if DBGrid.Columns[i].Visible then
      ColumnsWidth[i] := DBGrid.Canvas.TextWidth
        (DBGrid.Columns[i].title.Caption + '   ')
    else
      ColumnsWidth[i] := 0;
  if DBGrid.DataSource <> nil then
    DataSet := DBGrid.DataSource.DataSet
  else
    DataSet := nil;
  if (DataSet <> nil) and DataSet.Active then
  begin
    Bookmark := DataSet.GetBookmark;
    DataSet.DisableControls;
    try
      Count := 0;
      DataSet.First;
      while not DataSet.Eof and (Count < MaxRows) do
      begin
        for i := 0 to DBGrid.Columns.Count - 1 do
          if DBGrid.Columns[i].Visible then
            ColumnsWidth[i] := Max(ColumnsWidth[i],
              DBGrid.Canvas.TextWidth(DBGrid.Columns[i].Field.Text + '   '));
        Inc(Count);
        DataSet.Next;
      end;
    finally
      DataSet.GotoBookmark(Bookmark);
      DataSet.FreeBookmark(Bookmark);
      DataSet.EnableControls;
    end;
  end;
  Count := 0;
  for i := 0 to DBGrid.Columns.Count - 1 do
    if DBGrid.Columns[i].Visible then
    begin
      DBGrid.Columns[i].Width := ColumnsWidth[i];
      Inc(Count, ColumnsWidth[i]);
    end;
  Result := Count - DBGrid.ClientWidth;
end;

// ----------------------------------------------------------
//
// Function checks is TJsonObject has field and this field has not null value
//
{ TODO 1: [Helper] TJSONObject Class helpper and more minigful name expected }
function fieldAvaliable(jsObject: TJSONObject; const fieldName: string)
  : Boolean; inline;
begin
  Result := Assigned(jsObject.Values[fieldName]) and not jsObject.Values
    [fieldName].Null;
end;

{ TODO 1: [Helper] TJSONObject Class helpper and this method has two responsibilities }
// Warning! In-out var parameter
// extract separate:  GetIsoDateUtc
function IsValidIsoDateUtc(jsObj: TJSONObject; const Field: string;
  var dt: TDateTime): Boolean;
begin
  dt := 0;
  try
    dt := System.DateUtils.ISO8601ToDate(jsObj.Values[Field].Value, False);
    Result := True;
  except
    on E: Exception do
      Result := False;
  end
end;

{ TODO 1: [cleanups] Move into Utils.General }
function CheckEmail(const s: string): Boolean;
const
  EMAIL_REGEX = '^((?>[a-zA-Z\d!#$%&''*+\-/=?^_`{|}~]+\x20*|"((?=[\x01-\x7f])' +
    '[^"\\]|\\[\x01-\x7f])*"\x20*)*(?<angle><))?((?!\.)' +
    '(?>\.?[a-zA-Z\d!#$%&''*+\-/=?^_`{|}~]+)+|"((?=[\x01-\x7f])' +
    '[^"\\]|\\[\x01-\x7f])*")@(((?!-)[a-zA-Z\d\-]+(?<!-)\.)+[a-zA-Z]' +
    '{2,}|\[(((?(?<!\[)\.)(25[0-5]|2[0-4]\d|[01]?\d?\d))' +
    '{4}|[a-zA-Z\d\-]*[a-zA-Z\d]:((?=[\x01-\x7f])[^\\\[\]]|\\' +
    '[\x01-\x7f])+)\])(?(angle)>)$';
begin
  Result := System.RegularExpressions.TRegEx.IsMatch(s, EMAIL_REGEX);
end;

function BooksToDateTime(const s: string): TDateTime;
const
  months: array [1 .. 12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  m: string;
  y: string;
  i: Integer;
  mm: Integer;
  yy: Integer;
begin
  m := s.Substring(0, 3);
  y := s.Substring(4);
  mm := 0;
  for i := 1 to 12 do
    if months[i].ToUpper = m.ToUpper then
      mm := i;
  if mm = 0 then
    raise ERangeError.Create('Incorect mont name in the date: ' + s);
  yy := y.ToInteger();
  Result := EncodeDate(yy, mm, 1);
end;

{ TODO 2: [A] Method is too large. Comments is showing separate methods }
procedure TForm1.btnImportClick(Sender: TObject);
var
  frm: TFrameImport;
  tab: TChromeTab;
  jsData: TJSONArray;
  DBGrid1: TDBGrid;
  DataSrc1: TDataSource;
  DBGrid2: TDBGrid;
  DataSrc2: TDataSource;
  i: Integer;
  jsRow: TJSONObject;
  email: string;
  firstName: string;
  lastName: string;
  company: string;
  bookISBN: string;
  bookTitle: string;
  rating: Integer;
  oppinion: string;
  ss: array of string;
  v: string;
  dtReported: TDateTime;
  readerId: Variant;
  b: TBook;
  jsBooks: TJSONArray;
  jsBook: TJSONObject;
  TextBookReleseDate: string;
  b2: TBook;
begin
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Import new Books data from OpenAPI
  //
  { TODO 2: [A] Extract method. Read comments and use meaningful name }
  jsBooks := ImportBooksFromWebService(Client_API_Token);
  try
    for i := 0 to jsBooks.Count - 1 do
    begin
      jsBook := jsBooks.Items[i] as TJSONObject;
      b := TBook.Create;
      b.status := jsBook.Values['status'].Value;
      b.title := jsBook.Values['title'].Value;
      b.isbn := jsBook.Values['isbn'].Value;
      b.author := jsBook.Values['author'].Value;
      TextBookReleseDate := jsBook.Values['date'].Value;
      b.releseDate := BooksToDateTime(TextBookReleseDate);
      b.pages := (jsBook.Values['pages'] as TJSONNumber).AsInt;
      b.price := StrToCurr(jsBook.Values['price'].Value);
      b.currency := jsBook.Values['currency'].Value;
      b.description := jsBook.Values['description'].Value;
      b.imported := Now();
      b2 := FBooksConfig.GetBookList(blkAll).FindByISBN(b.isbn);
      if not Assigned(b2) then
      begin
        FBooksConfig.InsertNewBook(b);
        // ----------------------------------------------------------------
        // Append report into the database:
        // Fields: ISBN, Title, Authors, Status, ReleseDate, Pages, Price,
        // Currency, Imported, Description
        DataModMain.dsBooks.InsertRecord([b.isbn, b.title, b.author, b.status,
          b.releseDate, b.pages, b.price, b.currency, b.imported,
          b.description]);
      end;
    end;
  finally
    jsBooks.Free;
  end;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Create new frame, show it add to ChromeTabs
  // 1. Create TFrameImport.
  // 2. Embed frame in pnMain (show)
  // 3. Add new ChromeTab
  //
  { TODO 1: [Duplicated code] ChromeTabs1.Tabs.Add . Extract method. }
  // Read comments above to choose meaningful name
  frm := TFrameImport.Create(pnMain);
  frm.Parent := pnMain;
  frm.Visible := True;
  frm.Align := alClient;
  tab := ChromeTabs1.Tabs.Add;
  tab.Caption := 'Readers';
  tab.Data := frm;
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
  AutoSizeColumns(DBGrid1);
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Import new Reader Reports data from OpenAPI
  // - Load JSON from WebService
  // - Validate JSON and insert new a Readers into the Database
  //
  jsData := ImportReaderReportsFromWebService(Client_API_Token);
  { TODO 2: [D] Extract method. Block try-catch is separate responsibility }
  try
    for i := 0 to jsData.Count - 1 do
    begin
      { TODO 4: [A] Extract Reader Report code into the record TReaderReport (model layer) }
      { TODO 2: [F] Repeated code. Violation of the DRY rule }
      // Use TJSONObject helper Values return Variant.Null
      // ----------------------------------------------------------------
      //
      // Read JSON object
      //
      { TODO 4: [A] Move this code into record TReaderReport.LoadFromJSON }
      jsRow := jsData.Items[i] as TJSONObject;
      email := jsRow.Values['email'].Value;
      if fieldAvaliable(jsRow, 'firstname') then
        firstName := jsRow.Values['firstname'].Value
      else
        firstName := '';
      if fieldAvaliable(jsRow, 'lastname') then
        lastName := jsRow.Values['lastname'].Value
      else
        lastName := '';
      if fieldAvaliable(jsRow, 'company') then
        company := jsRow.Values['company'].Value
      else
        company := '';
      if fieldAvaliable(jsRow, 'book-isbn') then
        bookISBN := jsRow.Values['book-isbn'].Value
      else
        bookISBN := '';
      if fieldAvaliable(jsRow, 'book-title') then
        bookTitle := jsRow.Values['book-title'].Value
      else
        bookTitle := '';
      if fieldAvaliable(jsRow, 'rating') then
        rating := (jsRow.Values['rating'] as TJSONNumber).AsInt
      else
        rating := -1;
      if fieldAvaliable(jsRow, 'oppinion') then
        oppinion := jsRow.Values['oppinion'].Value
      else
        oppinion := '';
      // ----------------------------------------------------------------
      //
      // Validate imported Reader report
      //
      { TODO 2: [E] Move validation up. Before reading data }
      ValidateBookAndGetDateReported(jsRow, email, dtReported);
      // ----------------------------------------------------------------
      //
      // Locate book by ISBN
      //
      { TODO 2: [G] Extract method }
      b := FBooksConfig.GetBookList(blkAll).FindByISBN(bookISBN);
      if not Assigned(b) then
        raise Exception.Create('Invalid book isbn');
      // ----------------------------------------------------------------
      // Find the Reader in then database using an email address
      readerId := DataModMain.FindReaderByEmil(email);
      // ----------------------------------------------------------------
      //
      // Append a new reader into the database if requred:
      if VarIsNull(readerId) then
      begin
        { TODO 2: [G] Extract method }
        readerId := DataModMain.GetMaxValueInDataSet(DataModMain.dsReaders,
          'ReaderId') + 1;
        //
        // Fields: ReaderId, FirstName, LastName, Email, Company, BooksRead,
        // LastReport, ReadersCreated
        //
        DataModMain.dsReaders.AppendRecord([readerId, firstName, lastName,
          email, company, 1, dtReported, Now()]);
      end;
      // ----------------------------------------------------------------
      //
      // Append report into the database:
      // Fields: ReaderId, ISBN, Rating, Oppinion, Reported
      //
      DataModMain.dsReports.AppendRecord([readerId, bookISBN, rating, oppinion,
        dtReported]);
      // ----------------------------------------------------------------
      if FInDeveloperMode then
        Insert([rating.ToString], ss, maxInt);
    end;
    // ----------------------------------------------------------------
    if FInDeveloperMode then
      Caption := String.Join(' ,', ss);
    // ----------------------------------------------------------------
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
    AutoSizeColumns(DBGrid2);
  finally
    jsData.Free;
  end;
end;

procedure TForm1.ChromeTabs1ButtonCloseTabClick(Sender: TObject;
  ATab: TChromeTab; var Close: Boolean);
var
  obj: TObject;
begin
  obj := TObject(ATab.Data);
  (obj as TFrame).Free;
end;

{ TODO 1: [Helper] TWinControl class helper }
procedure HideAllChildFrames(AParenControl: TWinControl);
var
  i: Integer;
begin
  for i := AParenControl.ControlCount - 1 downto 0 do
    if AParenControl.Controls[i] is TFrame then
      (AParenControl.Controls[i] as TFrame).Visible := False;
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
      HideAllChildFrames(pnMain);
      (obj as TFrame).Visible := True;
    end;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  Extention: string;
  ExeName: string;
  ProjectFileName: string;
begin
  // ----------------------------------------------------------
  // Check: If we are in developer mode
  //
  // Developer mode id used to change application configuration
  // during test
  { TODO 1: [Helper] TApplication.IsDeveloperMode }
{$IFDEF DEBUG}
  Extention := '.dpr';
  ExeName := ExtractFileName(Application.ExeName);
  ProjectFileName := ChangeFileExt(ExeName, Extention);
  FInDeveloperMode := FileExists(ProjectFileName) or
    FileExists('..\..\' + ProjectFileName);
{$ELSE}
  FDevMod := False;
{$ENDIF}
  pnMain.Caption := '';
end;

procedure TForm1.ResizeBooksListBoxesInsideGroupBox(aGroupBox: TGroupBox);
var
  sum: Integer;
  avaliable: Integer;
  labelPixelHeight: Integer;
begin
  { TODO 1: [too complicated]  }
  // It's enought to do this:
  //   lbxBooksReaded.Height :=
  //     (lbxBooksReaded.Height + lbxBooksAvaliable2.Height) div 2;
  // method SumHeightForChildrens won't be used, but is intersting as a pattern
  with TBitmap.Create do
  begin
    Canvas.Font.Size := aGroupBox.Font.Height;
    labelPixelHeight := Canvas.TextHeight('Zg');
    Free;
  end;
  sum := SumHeightForChildrens(aGroupBox, [lbxBooksReaded, lbxBooksAvaliable2]);
  avaliable := aGroupBox.Height - sum - labelPixelHeight;
  if aGroupBox.AlignWithMargins then
    avaliable := avaliable - aGroupBox.Padding.Top - aGroupBox.Padding.Bottom;
  if lbxBooksReaded.AlignWithMargins then
    avaliable := avaliable - lbxBooksReaded.Margins.Top -
      lbxBooksReaded.Margins.Bottom;
  if lbxBooksAvaliable2.AlignWithMargins then
    avaliable := avaliable - lbxBooksAvaliable2.Margins.Top -
      lbxBooksAvaliable2.Margins.Bottom;
  lbxBooksReaded.Height := avaliable div 2;
end;

procedure TForm1.ValidateBookAndGetDateReported(jsRow: TJSONObject;
  email: string; var dtReported: TDateTime);
begin
  if not CheckEmail(email) then
    raise Exception.Create('Invalid email addres');
  if not IsValidIsoDateUtc(jsRow, 'created', dtReported) then
    raise Exception.Create('Invalid date. Expected ISO format');
end;

procedure TForm1.Splitter1Moved(Sender: TObject);
begin
  (Sender as TSplitter).Tag := 1;
end;

procedure TForm1.tmrAppReadyTimer(Sender: TObject);
var
  frm: TFrameWelcome;
  tab: TChromeTab;
  VersionNr: Integer;
  msg1: string;
  UserName: string;
  password: string;
  res: Variant;
  datasrc: TDataSource;
  DataGrid: TDBGrid;
begin
  tmrAppReady.Enabled := False;
  if FInDeveloperMode then
    ReportMemoryLeaksOnShutdown := True;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Create and show Welcome Frame
  //
  { TODO 2: [B] Extract method. Read comments and use meaningful }
  frm := TFrameWelcome.Create(pnMain);
  frm.Parent := pnMain;
  frm.Visible := True;
  frm.Align := alClient;
  tab := ChromeTabs1.Tabs.Add;
  tab.Caption := 'Welcome';
  tab.Data := frm;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // Connect to database server
  // Check application user and database structure (DB version)
  //
  // TODO 2: [!] Dependency on DataModMain.FDConnection1 (discuss LoD)
  // Move this code into the DataModule
  try
    UserName := FireDAC.Comp.Client.FDManager.ConnectionDefs.ConnectionDefByName
      (DataModMain.FDConnection1.ConnectionDefName).Params.UserName;
    password := AES128_Decrypt(SecurePassword, SecureKey);
    if password = '<null>' then
      password := '';
    DataModMain.FDConnection1.Open(UserName, password);
  except
    on E: FireDAC.Stan.Error.EFDDBEngineException do
    begin
      case E.kind of
        ekUserPwdInvalid:
          msg1 := SDBConnectionUserPwdInvalid;
        ekServerGone:
          msg1 := SDBServerGone;
      else
        msg1 := SDBConnectionError
      end;
      frm.AddInfo(0, msg1, True);
      frm.AddInfo(1, E.Message, False);
      exit;
    end;
  end;
  try
    res := DataModMain.FDConnection1.ExecSQLScalar(SQL_GetDatabaseVersion);
  except
    on E: EFDDBEngineException do
    begin
      msg1 := IfThen(E.kind = ekObjNotExists, SDBRequireCreate, SDBErrorSelect);
      frm.AddInfo(0, msg1, True);
      frm.AddInfo(1, E.Message, False);
      exit;
    end;
  end;
  VersionNr := res;
  if VersionNr <> ExpectedDatabaseVersionNr then
  begin
    frm.AddInfo(0, StrNotSupportedDBVersion, True);
    frm.AddInfo(1, 'Oczekiwana wersja bazy: ' +
      DBVersionToString(ExpectedDatabaseVersionNr), True);
    frm.AddInfo(1, 'Aktualna wersja bazy: ' + DBVersionToString
      (VersionNr), True);
  end;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  DataModMain.OpenDataSets;
  // ----------------------------------------------------------
  // ----------------------------------------------------------
  //
  // * Initialize ListBox'es for books
  // * Load books form database
  // * Setup drag&drop functionality for two list boxes
  // * Setup OwnerDraw mode
  //
  FBooksConfig := TBooksListBoxConfigurator.Create(self);
  FBooksConfig.PrepareListBoxes(lbxBooksReaded, lbxBooksAvaliable2);
  // ----------------------------------------------------------
  // ----------------------------`------------------------------
  //
  // Create Books Grid for Quality Tests
  if FInDeveloperMode and ShowBooksGrid then
  begin
    datasrc := TDataSource.Create(frm);
    DataGrid := TDBGrid.Create(frm);
    DataGrid.AlignWithMargins := True;
    DataGrid.Parent := frm;
    DataGrid.Align := alClient;
    DataGrid.DataSource := datasrc;
    datasrc.DataSet := DataModMain.dsBooks;
    AutoSizeColumns(DataGrid);
  end;
end;

end.

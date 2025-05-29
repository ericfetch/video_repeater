#define MyAppName "视频复读机"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "语言学习工具"
#define MyAppExeName "video_repeater_study_language.exe"

[Setup]
; 注意: AppId的值为唯一标识此应用程序。
; 不要在其他应用程序中使用相同的AppId值。
AppId={{E8F5A8C0-9F3E-4F7A-B6D2-8D9D2F0A9A1B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; 以下行取消注释，以在"开始"菜单中创建一个目录。
CreateAppDir=yes
OutputBaseFilename=视频复读机安装程序
Compression=lzma
SolidCompression=yes
; 请求管理员权限
PrivilegesRequired=admin

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent 
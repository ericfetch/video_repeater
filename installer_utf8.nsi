; UTF-8编码
Unicode true

; 定义应用名称和版本
!define APPNAME "VideoRepeater"
!define APPDISPLAYNAME "视频复读机"
!define APPVERSION "1.0.0"
!define COMPANYNAME "Language Learning Tools"
!define DESCRIPTION "视频语言学习工具"

; 安装程序名称
Name "${APPDISPLAYNAME}"
OutFile "视频复读机安装程序.exe"

; 默认安装目录
InstallDir "$PROGRAMFILES64\${APPNAME}"

; 请求管理员权限
RequestExecutionLevel admin

; 界面设置
!include "MUI2.nsh"
!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"

; 安装页面
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; 卸载页面
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; 语言
!insertmacro MUI_LANGUAGE "SimpChinese"

; 安装部分
Section "安装" SecInstall
  SetOutPath "$INSTDIR"
  
  ; 复制应用文件
  File /r "build\windows\x64\runner\Release\*.*"
  
  ; 创建卸载注册表项
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayName" "${APPDISPLAYNAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "InstallLocation" "$\"$INSTDIR$\""
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" "Publisher" "${COMPANYNAME}"
  
  ; 写入卸载程序
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
  ; 创建开始菜单快捷方式
  CreateDirectory "$SMPROGRAMS\${APPDISPLAYNAME}"
  CreateShortcut "$SMPROGRAMS\${APPDISPLAYNAME}\${APPDISPLAYNAME}.lnk" "$INSTDIR\video_repeater_study_language.exe"
  CreateShortcut "$SMPROGRAMS\${APPDISPLAYNAME}\卸载${APPDISPLAYNAME}.lnk" "$INSTDIR\uninstall.exe"
  
  ; 创建桌面快捷方式
  CreateShortcut "$DESKTOP\${APPDISPLAYNAME}.lnk" "$INSTDIR\video_repeater_study_language.exe"
SectionEnd

; 卸载部分
Section "Uninstall"
  ; 删除安装的文件
  RMDir /r "$INSTDIR"
  
  ; 删除开始菜单项
  RMDir /r "$SMPROGRAMS\${APPDISPLAYNAME}"
  
  ; 删除桌面快捷方式
  Delete "$DESKTOP\${APPDISPLAYNAME}.lnk"
  
  ; 删除注册表项
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd 
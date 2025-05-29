# 创建安装包脚本
$sourcePath = "build\windows\x64\runner\Release"
$outputZip = "视频复读机.zip"

# 创建临时目录
$tempDir = "temp_installer"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -Path $tempDir -ItemType Directory | Out-Null

# 复制发布文件到临时目录
Copy-Item -Path "$sourcePath\*" -Destination $tempDir -Recurse

# 创建安装批处理文件
$installBat = @"
@echo off
echo 正在安装视频复读机...
set INSTALL_DIR=%LOCALAPPDATA%\视频复读机
mkdir "%INSTALL_DIR%"
xcopy /e /i /y "%~dp0*" "%INSTALL_DIR%\"
echo 正在创建桌面快捷方式...
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $d = [Environment]::GetFolderPath('Desktop'); $s = $ws.CreateShortcut($d + '\视频复读机.lnk'); $s.TargetPath = '$env:LOCALAPPDATA\视频复读机\video_repeater_study_language.exe'; $s.Save()"
echo 安装完成！
pause
"@

$installBat | Out-File -FilePath "$tempDir\安装.bat" -Encoding Default

# 创建卸载批处理文件
$uninstallBat = @"
@echo off
echo 正在卸载视频复读机...
del "%USERPROFILE%\Desktop\视频复读机.lnk"
rmdir /s /q "%LOCALAPPDATA%\视频复读机"
echo 卸载完成！
pause
"@

$uninstallBat | Out-File -FilePath "$tempDir\卸载.bat" -Encoding Default

# 创建README文件
$readmeTxt = @"
视频复读机 - 安装说明

1. 运行"安装.bat"文件安装应用
2. 从桌面快捷方式启动应用
3. 如需卸载，运行"卸载.bat"文件

注意：安装过程需要管理员权限
"@

$readmeTxt | Out-File -FilePath "$tempDir\自述文件.txt" -Encoding Default

# 压缩应用程序文件
Write-Host "正在创建安装包..."
Compress-Archive -Path "$tempDir\*" -DestinationPath $outputZip -Force

# 清理临时文件
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "安装包已创建: $outputZip"
Write-Host "请解压后运行'安装.bat'文件以安装应用。" 
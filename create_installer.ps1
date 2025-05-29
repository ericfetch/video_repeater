# 创建安装包脚本
$sourcePath = "build\windows\x64\runner\Release"
$outputZip = "VideoRepeater.zip"
$outputExe = "VideoRepeater-Setup.exe"

# 创建临时目录
$tempDir = "temp_installer"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -Path $tempDir -ItemType Directory | Out-Null

# 复制发布文件到临时目录
Copy-Item -Path "$sourcePath\*" -Destination $tempDir -Recurse

# 创建桌面和开始菜单快捷方式的脚本
$shortcutScript = @"
$desktopPath = [System.Environment]::GetFolderPath('Desktop')
$startMenuPath = [System.Environment]::GetFolderPath('StartMenu') + "\Programs\视频复读机"

# 创建开始菜单目录
if (-not (Test-Path $startMenuPath)) {
    New-Item -Path $startMenuPath -ItemType Directory | Out-Null
}

# 创建桌面快捷方式
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$desktopPath\视频复读机.lnk")
$Shortcut.TargetPath = "$PSScriptRoot\video_repeater_study_language.exe"
$Shortcut.Save()

# 创建开始菜单快捷方式
$Shortcut = $WshShell.CreateShortcut("$startMenuPath\视频复读机.lnk")
$Shortcut.TargetPath = "$PSScriptRoot\video_repeater_study_language.exe"
$Shortcut.Save()

Write-Host "安装完成！快捷方式已创建。"
"@

# 将快捷方式脚本保存到临时目录
$shortcutScript | Out-File -FilePath "$tempDir\create_shortcuts.ps1" -Encoding utf8

# 创建自解压安装脚本
$extractScript = @"
# 解压并安装
$extractPath = "$env:LOCALAPPDATA\视频复读机"

# 创建目标目录
if (-not (Test-Path $extractPath)) {
    New-Item -Path $extractPath -ItemType Directory | Out-Null
}

# 解压文件
Expand-Archive -Path "$PSScriptRoot\app.zip" -DestinationPath $extractPath -Force

# 创建快捷方式
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `$extractPath\create_shortcuts.ps1" -Wait

Write-Host "视频复读机已安装完成！"
pause
"@

# 将解压脚本保存到临时目录
$extractScript | Out-File -FilePath "$tempDir\install.ps1" -Encoding utf8

# 压缩应用程序文件
Compress-Archive -Path "$tempDir\*" -DestinationPath "app.zip" -Force

# 创建最终的安装脚本
$finalScript = @"
# 视频复读机安装程序
$Host.UI.RawUI.WindowTitle = "视频复读机安装程序"
Write-Host "正在安装视频复读机，请稍候..." -ForegroundColor Green

# 解压并安装
$extractPath = "$env:LOCALAPPDATA\视频复读机"

# 创建目标目录
if (-not (Test-Path $extractPath)) {
    New-Item -Path $extractPath -ItemType Directory | Out-Null
}

# 解压文件
Expand-Archive -Path "$PSScriptRoot\app.zip" -DestinationPath $extractPath -Force

# 创建快捷方式
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `$extractPath\create_shortcuts.ps1" -Wait

Write-Host "视频复读机已安装完成！" -ForegroundColor Green
Write-Host "按任意键退出..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
"@

# 将最终脚本保存
$finalScript | Out-File -FilePath "install.ps1" -Encoding utf8

# 创建自解压可执行文件
Write-Host "正在创建安装包..."

# 使用PS2EXE将脚本转换为EXE（如果已安装）
if (Get-Command -Name "ps2exe" -ErrorAction SilentlyContinue) {
    ps2exe -inputFile "install.ps1" -outputFile $outputExe -iconFile "windows\runner\resources\app_icon.ico" -title "视频复读机安装程序" -noConsole
    Write-Host "安装包已创建: $outputExe"
} else {
    # 如果没有PS2EXE，则创建一个批处理文件来运行PowerShell脚本
    $batchContent = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "%~dp0install.ps1"
"@
    $batchContent | Out-File -FilePath "Install.bat" -Encoding ascii
    Write-Host "安装包已创建: Install.bat 和 app.zip"
    Write-Host "注意: 要创建单个EXE文件，请安装PS2EXE模块: Install-Module -Name ps2exe"
}

# 清理临时文件
Remove-Item -Path $tempDir -Recurse -Force
Remove-Item -Path "install.ps1" -Force

Write-Host "完成！" 
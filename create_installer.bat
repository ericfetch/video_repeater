@echo off
echo 正在创建视频复读机安装包...

rem 创建临时目录
if exist temp_installer rmdir /s /q temp_installer
mkdir temp_installer

rem 复制Release文件到临时目录
xcopy /e /i /y "build\windows\x64\runner\Release\*" "temp_installer\"

rem 创建安装批处理文件
echo @echo off > temp_installer\安装.bat
echo echo 正在安装视频复读机... >> temp_installer\安装.bat
echo mkdir "%USERPROFILE%\Desktop\视频复读机" >> temp_installer\安装.bat
echo xcopy /e /i /y "%%~dp0*" "%%USERPROFILE%%\Desktop\视频复读机\" >> temp_installer\安装.bat
echo echo 正在创建桌面快捷方式... >> temp_installer\安装.bat
echo powershell -Command "$s = New-Object -ComObject WScript.Shell; $d = [System.Environment]::GetFolderPath('Desktop'); $shortcut = $s.CreateShortcut($d + '\视频复读机.lnk'); $shortcut.TargetPath = $env:USERPROFILE + '\Desktop\视频复读机\video_repeater_study_language.exe'; $shortcut.Save()" >> temp_installer\安装.bat
echo echo 安装完成！请从桌面上的快捷方式启动应用。 >> temp_installer\安装.bat
echo pause >> temp_installer\安装.bat

rem 创建卸载批处理文件
echo @echo off > temp_installer\卸载.bat
echo echo 正在卸载视频复读机... >> temp_installer\卸载.bat
echo del "%USERPROFILE%\Desktop\视频复读机.lnk" >> temp_installer\卸载.bat
echo rmdir /s /q "%USERPROFILE%\Desktop\视频复读机" >> temp_installer\卸载.bat
echo echo 卸载完成！ >> temp_installer\卸载.bat
echo pause >> temp_installer\卸载.bat

rem 创建自解压包
powershell -Command "Compress-Archive -Path 'temp_installer\*' -DestinationPath '视频复读机.zip' -Force"

rem 清理临时文件
rmdir /s /q temp_installer

echo 安装包已创建: 视频复读机.zip
echo 请解压后运行"安装.bat"文件以安装应用。
pause 
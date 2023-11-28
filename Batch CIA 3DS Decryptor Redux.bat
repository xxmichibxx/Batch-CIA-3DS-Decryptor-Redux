@echo off
color 1F
mode con cols=60 lines=25
set ScriptBuild=2023-11-28
set state=0
set rootdir=%cd%
set content=log\CTR_Content.txt
title Batch CIA 3DS Decryptor Redux - build %Scriptbuild%
if not exist "log" mkdir log
echo Batch CIA 3DS Decryptor Redux>log\programlog.txt
echo [i] = Information>>log\programlog.txt
echo [!] = Error>>log\programlog.txt
echo [#] = Debug>>log\programlog.txt
echo [^^] = Warning>>log\programlog.txt
echo.>>log\programlog.txt
echo Batch CIA 3DS Decryptor Redux - build %Scriptbuild%>>log\programlog.txt
echo %date% - %time:~0,-3% = [i] Script started>>log\programlog.txt
if not "%PROCESSOR_ARCHITECTURE%"=="AMD64" goto unsupported
cls
echo.
echo   ########################################################
echo   ###                                                  ###
echo   ### Batch CIA 3DS Decryptor Redux - build %Scriptbuild% ###
echo   ###                                                  ###
echo   ########################################################
echo.
echo.
echo   Decrypting...
echo.
setlocal EnableDelayedExpansion
for %%a in (bin\*.ncch) do (
	echo %date% - %time:~0,-3% = [i] Found unsed NCCH file. Start deleting.>>log\programlog.txt
	del "%%a"
)
for %%a in (*.3ds) do (
	echo %date% - %time:~0,-3% = [i] Found 3DS file. Start decrypting.>>log\programlog.txt
	set CUTN=%%~na
	if /i x!CUTN!==x!CUTN:decrypted=! (
		echo | bin\decrypt.exe "%%a" >nul
		set state=1
		set ARG=
		for %%f in ("bin\!CUTN!.*.ncch") do (
			if %%f==bin\!CUTN!.Main.ncch set i=0
			if %%f==bin\!CUTN!.Manual.ncch set i=1
			if %%f==bin\!CUTN!.DownloadPlay.ncch set i=2
			if %%f==bin\!CUTN!.Partition4.ncch set i=3
			if %%f==bin\!CUTN!.Partition5.ncch set i=4
			if %%f==bin\!CUTN!.Partition6.ncch set i=5
			if %%f==bin\!CUTN!.N3DSUpdateData.ncch set i=6
			if %%f==bin\!CUTN!.UpdateData.ncch set i=7
			set ARG=!ARG! -i "%%f:!i!:!i!"
		)
		bin\makerom.exe -f cci -ignoresign -target p -o "%rootdir%\!CUTN!-decrypted.3ds"!ARG! >nul 2>nul
		if not exist "!CUTN!-decrypted.3ds" (
			echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!CUTN!.3ds]>>log\programlog.txt
			set state=0
		)
	)
	for %%a in (bin\*.ncch) do del /s "%%a" >nul 2>&1
)
for %%a in (*.cia) do (
	set CUTN=%%~na
	if /i x!CUTN!==x!CUTN:decrypted=! (
		if exist "!content!" del /s "!content!" >nul 2>&1
		set CryptoKey=1
		set CIAType=0
		bin\ctrtool.exe --seeddb=bin\seeddb.bin "%%a" >!content!
		set FILE="!content!"
		for /f "skip=1 delims=" %%x in ('findstr "TitleId" !content!') do set "TitleId=%%x"
		for /f "delims=" %%y in ('findstr /c:"Crypto Key" !content!') do set "CryptoKey=%%y"
		for /f "tokens=4 delims= " %%z in ('findstr "TitleVersion" !content!') do set "TitleVersion=%%z"
		set TitleId=!TitleId:~18!
		set TitleVersion=!TitleVersion:~1,-1!
		echo "!CryptoKey!" | findstr "Secure" >nul 2>nul
		if "!errorlevel!"=="0" (
			echo %date% - %time:~0,-3% = [i] Found CIA file. Start decrypting.>>log\programlog.txt
        	set /a i=0
        	set ARG=
        	REM eShop Gamecard Applications
        	findstr /i /pr "00040000" !FILE! | findstr /C:"Title id" >nul 2>nul
        	if not errorlevel 1 (
        		set state=1
        		echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" [!TitleId! v!TitleVersion!] is a eShop or Gamecard title>>log\programlog.txt
        		set CIAType=1
        		echo | bin\decrypt.exe "%%a" >nul 2>nul
        		for %%f in ("bin\!CUTN!.*.ncch") do (
        			set ARG=!ARG! -i "%%f:!i!:!i!"
        			set /a i+=1
        		)
        		echo %date% - %time:~0,-3% = [i] Calling makerom for eShop or Gamecard CIA [!TitleId!]>>log\programlog.txt
        		bin\makerom.exe -f cia -ignoresign -target p -o "%rootdir%\!CUTN!-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>nul
				if not exist "%rootdir%\!CUTN!-decrypted.cia" (
					echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!TitleId! v!TitleVersion!]>>log\programlog.txt
					set state=0
				)
        	)
        	REM System Applications
        	findstr /i /pr "00040010 0004001b 00040030 0004009b 000400db 00040130 00040138" !FILE! | findstr /C:"Title id" >nul 2>nul
        	if not errorlevel 1 (
        		set state=1
        		findstr /i /pr "00040010" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a system application>>log\programlog.txt
        		findstr /i /pr "0004001b 000400db" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a system data archive>>log\programlog.txt
        		findstr /i /pr "00040030" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a system applet>>log\programlog.txt
        		findstr /i /pr "0004009b" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a shared data archive>>log\programlog.txt
        		findstr /i /pr "00040130" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a system module>>log\programlog.txt
        		findstr /i /pr "00040138" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" is a system firmware>>log\programlog.txt
        		set CIAType=1
        		echo | bin\decrypt.exe "%%a" >nul 2>nul
        		for %%f in ("bin\!CUTN!.*.ncch") do (
        			set ARG=!ARG! -i "%%f:!i!:!i!"
        			set /a i+=1
        		)
        		echo %date% - %time:~0,-3% = [i] Calling makerom for system title CIA [!TitleId!]>>log\programlog.txt
        		bin\makerom.exe -f cia -ignoresign -target p -o "%rootdir%\!CUTN!-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>nul
				if not exist "%rootdir%\!CUTN!-decrypted.cia" (
					echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!TitleId! v!TitleVersion!]>>log\programlog.txt
					set state=0
				) else (
					echo %date% - %time:~0,-3% = [i] Decrypting succeeded for [!TitleId! v!TitleVersion!]>>log\programlog.txt
				)
        	)
        	REM Demos
        	findstr /i /pr "00040002" !FILE! | findstr /C:"Title id" >nul 2>nul
        	if not errorlevel 1 (
        		set state=1
        		echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" [!TitleId! v!TitleVersion!] is a demo title>>log\programlog.txt
        		set CIAType=1
        		echo | bin\decrypt.exe "%%a" >nul 2>nul
        		for %%f in ("bin\!CUTN!.*.ncch") do (
        			set ARG=!ARG! -i "%%f:!i!:!i!"
        			set /a i+=1
        		)
        		echo %date% - %time:~0,-3% = [i] Calling makerom for demo CIA [!TitleId!]>>log\programlog.txt
        		bin\makerom.exe -f cia -ignoresign -target p -o "%rootdir%\!CUTN!-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>nul
				if not exist "%rootdir%\!CUTN!-decrypted.cia" (
					echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!TitleId! v!TitleVersion!]>>log\programlog.txt
					set state=0
				) else (
					echo %date% - %time:~0,-3% = [i] Decrypting succeeded for [!TitleId! v!TitleVersion!]>>log\programlog.txt
				)
        	)
        	REM Patches and DLCs
        	findstr /i /pr "0004000e 0004008c" !FILE! | findstr /C:"Title id" >nul 2>nul
        	if not errorlevel 1 (
        		set state=1
        		echo %date% - %time:~0,-3% = [i] CIA file "!CUTN!.cia" [!TitleId! v!TitleVersion!] is a update or DLC title>>log\programlog.txt
        		set CIAType=1
        		set TEXT="ContentId:"
        		set /a X=0
        		echo | bin\decrypt.exe "%%a" >nul 2>nul
        		for %%h in ("bin\!CUTN!.*.ncch") do (
        			set NCCHN=%%~nh
        			set /a n=bin\!NCCHN:%%~na.=!
        			if !n! gtr !X! set /a X=!n!
				)
				for /f "delims=" %%d in ('findstr /c:!TEXT! !FILE!') do (
					set CONLINE=%%d
					call :EXF
				)
				REM Patches
				findstr /i /pr "0004000e" !FILE! | findstr /C:"Title id" >nul 2>nul
				if not errorlevel 1 (
					echo %date% - %time:~0,-3% = [i] Calling makerom for update CIA [!TitleId! v!TitleVersion!]>>log\programlog.txt
					bin\makerom.exe -f cia -ignoresign -target p -o "!CUTN! Patch-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>nul
					if not exist "%rootdir%\!CUTN!-decrypted.cia" (
						echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!TitleId! v!TitleVersion!]>>log\programlog.txt
						set state=0
					) else (
						echo %date% - %time:~0,-3% = [i] Decrypting succeeded for [!TitleId! v!TitleVersion!]>>log\programlog.txt
					)
				)
				REM DLCs
				findstr /i /pr "0004008c" !FILE! | findstr /C:"Title id" >nul 2>nul
				if not errorlevel 1 (
					echo %date% - %time:~0,-3% = [i] Calling makerom for DLC CIA [!TitleId! v!TitleVersion!]>>log\programlog.txt
					bin\makerom.exe -f cia -dlc -ignoresign -target p -o "!CUTN! DLC-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>nul
					if not exist "%rootdir%\!CUTN!-decrypted.cia" (
						echo %date% - %time:~0,-3% = [^^!] Decrypting failed for [!TitleId! v!TitleVersion!]>>log\programlog.txt
						set state=0
					) else (
						echo %date% - %time:~0,-3% = [i] Decrypting succeeded for [!TitleId! v!TitleVersion!]>>log\programlog.txt
					)
				)
			)
			if "!CIATYPE!"=="0" echo %date% - %time:~0,-3% = [^^!] Could not determine CIA type [!CUTN!.cia]>>log\programlog.txt
		) else (
			echo "!CryptoKey!" | findstr "None" >nul 2>nul
			if "!errorlevel!"=="0" (
				echo %date% - %time:~0,-3% = [^^!] CIA file "!CUTN!.cia" [!TitleId! v!TitleVersion!] is already decrypted>>log\programlog.txt
			) else (
				set /p ctrtool_data=<!content!
				echo "!ctrtool_data!" | findstr "ERROR" >nul 2>nul
				if "!errorlevel!"=="0" echo %date% - %time:~0,-3% = [^^!] CIA is invalid [!CUTN!.cia]>>log\programlog.txt
			)
		)
		REM TWL titles
		findstr /i /pr "00048005 0004800f 00048005" !FILE! >nul 2>nul
		if "!errorlevel!"=="0" (
			findstr /i /pr "00048005" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CTRTool does not support TWL titles "!CUTN!.cia" [!TitleId! v!TitleVersion!] [System Application]>>log\programlog.txt
			findstr /i /pr "0004800f" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CTRTool does not support TWL titles "!CUTN!.cia" [!TitleId! v!TitleVersion!] [System Data Archive]>>log\programlog.txt
			findstr /i /pr "00048005" !FILE! | findstr /C:"Title id" echo %date% - %time:~0,-3% = [i] CTRTool does not support TWL titles "!CUTN!.cia" [!TitleId! v!TitleVersion!] [DSiWare Ports]>>log\programlog.txt
		)
	)
	for %%a in (bin\*.ncch) do del /s "%%a" >nul 2>&1
)
if exist "!content!" del /s "!content!" >nul 2>&1
if "%state%"=="0" goto noFilesDecrypted
echo %date% - %time:~0,-3% = [i] Decrypting process succeeded>>log\programlog.txt
cls
echo.
echo   ########################################################
echo   ###                                                  ###
echo   ### Batch CIA 3DS Decryptor Redux - build %Scriptbuild% ###
echo   ###                                                  ###
echo   ########################################################
echo.
echo.
echo   Decrypting finished^^!
echo.
echo   Please review "log\programlog.txt" for more details.
echo.
echo   Press any key to exit.
echo.
pause
echo %date% - %time:~0,-3% = [i] Script execution ended>>log\programlog.txt
exit

:EXF
if !X! geq !i! (
	if exist !CUTN!.!i!.ncch (
		set CONLINE=!CONLINE:~24,8!
		call :GETX !CONLINE!, ID
		set ARG=!ARG! -i "!CUTN!.!i!.ncch:!i!:!ID!"
		set /a i+=1
	) else (
		set /a i+=1
		goto EXF
	)
)
exit/B

:GETX v dec
set /a dec=0x%~1
if [%~2] neq [] set %~2=%dec%
exit/b

:noFilesDecrypted
echo %date% - %time:~0,-3% = [i] No files where decrypted>>log\programlog.txt
cls
echo.
echo   ########################################################
echo   ###                                                  ###
echo   ### Batch CIA 3DS Decryptor Redux - build %Scriptbuild% ###
echo   ###                                                  ###
echo   ########################################################
echo.
echo.
echo   No files where decrypted^^!
echo.
echo   Please review "log\programlog.txt" for more details.
echo.
echo   Press any key to exit.
echo.
echo %date% - %time:~0,-3% = [i] Script execution ended>>log\programlog.txt
pause
endlocal
exit

:unsupported
echo %date% - %time:~0,-3% = [^!] 32-bit operating systems are not supported>>log\programlog.txt
cls
echo.
echo   ########################################################
echo   ###                                                  ###
echo   ### Batch CIA 3DS Decryptor Redux - build %Scriptbuild% ###
echo   ###                                                  ###
echo   ########################################################
echo.
echo.
echo.
echo.
echo   This script only supports 64-bit operating systems^!
echo   Script execution halted^!
echo.
echo   Press any key to exit.
echo.
echo %date% - %time:~0,-3% = [i] Script execution ended>>log\programlog.txt
pause
exit
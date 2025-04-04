@echo off
color 1F
mode 64, 26
cd /d "%~dp0"
setlocal EnableDelayedExpansion
set ScriptVersion=v1.0.6.1
set totalCount=0
set finalCount=0
set count3DS=0
set countCIA=0
set CIAErrCount=0
set CCIErrCount=0
set DSErrCount=0
set convertToCCI=0
set golfEvent=0
set NCCHDeleted=0
set FancyArt=0
set VersionExtended=0
set rootdir=%cd%
set content=bin^\CTR_Content.txt
set logfile=log^\programlog.txt
if not "%ScriptVersion:~6%"=="" set VersionExtended=1
if not exist "log" mkdir log
title Batch CIA 3DS Decryptor Redux !ScriptVersion!
echo Batch CIA 3DS Decryptor Redux>!logfile!
echo [i] = Information>>!logfile!
echo [^^] = Warning>>!logfile!
echo [^^!] = Error>>!logfile!
echo:>>!logfile!
echo Batch CIA 3DS Decryptor Redux !ScriptVersion!>>!logfile!
echo %date% - %time:~0,-3% = [i] Script started>>!logfile!
if not "%PROCESSOR_ARCHITECTURE%"=="AMD64" goto unsupported
ver | find "5.2" >nul
if "%errorlevel%"=="0" goto unsupported
for %%a in (bin\*.ncch) do (
	if not "!NCCHDeleted!"=="1" echo %date% - %time:~0,-3% = [i] Found unused NCCH file[s]. Start deleting.>>!logfile!
	del "%%a" >nul 2>&1
	set NCCHDeleted=1
)
set "validchars=-_abcdefghijklmnopqrstuvwxyz1234567890. "
for %%b in (*) do (
	set "newname="
	set "oldname=%%b"
	call :validate
	if /i "%%b" neq "!newname!" ren "%%~sb" "!newname!" 2>nul
)
for %%f in (*.cia) do (
	echo %%f | find "-decrypted" >nul
	if "!errorlevel!"=="1" set /a countCIA+=1
)
for %%f in (*.3ds) do (
	echo %%f | find "-decrypted" >nul
	if "!errorlevel!"=="1" set /a count3DS+=1
)
set /a totalCount=!countCIA!+!count3DS!
if "!totalCount!"=="0" goto noFilesFound
if !countCIA! GEQ 1 (
	cls
	echo:
	call :ReduxBanner
	echo:
	echo:
	if "!countCIA!"=="1" (
		echo   A CIA file was found. Do you want to convert it to CCI^?
	) else (
		echo   !countCIA! CIA files were found. Do you want to convert them to CCI^?
	)
	echo   Please be aware that this doesn^'t work with the following
	echo   titles:
	echo:
	echo   - Downloadable Content [DLC]
	echo   - eShop Demos
	echo   - System titles
	echo   - TWL titles [DSi]
	echo   - Updates
	echo:
	echo   This applies to all CIA files that have been found.
	echo   The default option is No [N]. If you^'re unsure choose No.
	echo:
	echo   [Y] Yes
	echo   [N] No
	echo:
	set /p question=Enter: 
	if /i "!question!"=="y" set convertToCCI=1
	if /i "!question!"=="1" set convertToCCI=1
)
cls
echo:
call :ReduxBanner
echo:
echo:
echo   Decrypting...
call :ReduxFancyArt
if not "!count3DS!"=="0" ( 
	if "!count3DS!"=="1" echo %date% - %time:~0,-3% = [i] Found !count3DS! 3DS file. Start decrypting...>>!logfile!
	if !count3DS! GTR 1 echo %date% - %time:~0,-3% = [i] Found !count3DS! 3DS files. Start decrypting...>>!logfile!
)
for %%a in (*.3ds) do (
	set FileName=%%~na
	set fullFileName=%%~nxa
	if not exist "!FileName!-decrypted.cci" (
		if /i x!FileName!==x!FileName:decrypted=! (
			call :analyzeFile3DS
			echo "!CryptoKey!" | findstr "None" >nul 2>&1
			if not "!errorlevel!"=="0" (
				echo | bin\decrypt.exe "%%a%" >nul
				call :subroutineRename
				set ARG=
				for %%f in ("bin\tmp.*.ncch") do (
					if %%f==bin\tmp.Main.ncch set i=0
					if %%f==bin\tmp.Manual.ncch set i=1
					if %%f==bin\tmp.DownloadPlay.ncch set i=2
					if %%f==bin\tmp.Partition4.ncch set i=3
					if %%f==bin\tmp.Partition5.ncch set i=4
					if %%f==bin\tmp.Partition6.ncch set i=5
					if %%f==bin\tmp.N3DSUpdateData.ncch set i=6
					if %%f==bin\tmp.UpdateData.ncch set i=7
					set ARG=!ARG! -i "%%f:!i!:!i!"
				)
				bin\makerom.exe -f cci -ignoresign -target p -o "!FileName!-decrypted.cci"!ARG! >nul 2>&1
				if not exist "!FileName!-decrypted.cci" (
					echo %date% - %time:~0,-3% = [^^!] Decrypting failed for file "!FileName!.3ds">>!logfile!
					set /a DSErrCount+=1
				) else (
					echo %date% - %time:~0,-3% = [i] Decrypting succeeded for file "!FileName!.3ds">>!logfile!
					set /a finalCount+=1
				)
			) else (
				echo %date% - %time:~0,-3% = [^^^^] 3DS file "!FileName!.3ds" [!TitleId! v!TitleVersion!] is already decrypted>>!logfile!
				set /a DSErrCount+=1
			)
		)
		for %%a in (bin\*.ncch) do del /s "%%a" >nul 2>&1
	) else (
		echo %date% - %time:~0,-3% = [^^^^] 3DS file "!FileName!.3ds" was already decrypted>>!logfile!
		set /a finalCount+=1
	)
)
if not "!countCIA!"=="0" ( 
	if "!countCIA!"=="1" echo %date% - %time:~0,-3% = [i] Found !countCIA! CIA file. Start decrypting...>>!logfile!
	if !countCIA! GTR 1 echo %date% - %time:~0,-3% = [i] Found !countCIA! CIA files. Start decrypting...>>!logfile!
)
for %%a in (*.cia) do (
	set FileName=%%~na
	set fullFileName=%%~nxa
	if exist "!FileName!*-decrypted.cia" (
		if "!convertToCCI!"=="1" (
			if not exist "!FileName!*-decrypted.cci" (
				bin\ctrtool.exe --seeddb=bin\seeddb.bin "!fullFileName!" >!content!
				set FILE=!content!
				call :analyzeFileCIA
				call :convertToCCIFunction
			)
		) else (
			echo %date% - %time:~0,-3% = [^^^^] CIA file "!FileName!.cia" was already decrypted>>!logfile!
			set /a finalCount+=1
		)
	) else (
		echo !FileName! | find "-decrypted" >nul
		if not "!errorlevel!"=="0" (
			if "!convertToCCI!"=="1" (
				if exist "!FileName!*-decrypted.cci" (
					echo %date% - %time:~0,-3% = [^^^^] CIA file "!FileName!.cia" was already converted into CCI>>!logfile!
					set /a finalCount+=1
				) else (
					if not exist "!FileName!*-decrypted.cia" (
						call :CIAFunction
					)
					if not exist "!FileName!*-decrypted.cci" if exist "!FileName!*-decrypted.cia" (
						call :convertToCCIFunction
					)
				)
			) else (
				call :CIAFunction
			)
		)
	)
	for %%a in (bin\*.ncch) do del /s "%%a" >nul 2>&1
)
if exist "!content!" del /s "!content!" >nul 2>&1
if "!finalCount!"=="0" goto noFilesDecrypted
if !DSErrCount! GEQ 1 goto someFilesDecrypted
if !CCIErrCount! GEQ 1 goto someFilesDecrypted
if !CIAErrCount! GEQ 1 goto someFilesDecrypted
if not "!finalCount!"=="!totalCount!" goto someFilesDecrypted
goto FilesDecrypted

:EXF
if !X! geq !i! (
	if exist bin\tmp.!i!.ncch (
		set CONLINE=!CONLINE:~24,8!
		call :GETX !CONLINE!, ID
		set ARG=!ARG! -i "bin\tmp.!i!.ncch:!i!:!ID!"
		set /a i+=1
	) else (
		set /a i+=1
		goto EXF
	)
)
exit /b

:GETX v dec
set /a dec=0x%~1
if [%~2] neq [] set %~2=%dec%
exit /b

:subroutineRename
for %%F in (bin\*.ncch) do (
	set "NCCHName=%%F"
	ren "!NCCHName!" "tmp.*.ncch"
)
exit /b

:CIAFunction
if /i x!FileName!==x!FileName:decrypted=! (
	if exist "!content!" del /s "!content!" >nul 2>&1
	bin\ctrtool.exe --seeddb=bin\seeddb.bin "!fullFileName!" >!content!
	set FILE=!content!
	set CryptoKey=1
	set CIAType=0
	call :analyzeFileCIA
	echo "!CryptoKey!" | findstr "Secure" >nul 2>&1
	if "!errorlevel!"=="0" (
		set /a i=0
		set ARG=
		REM eShop Gamecard Applications
		echo "!TitleId!" | findstr /i "00040000" >nul 2>&1
		if not errorlevel 1 (
			echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a eShop or Gamecard title>>!logfile!
			set CIAType=1
			echo | bin\decrypt.exe "!FileName!.cia" >nul 2>&1
			call :subroutineRename
			for %%f in ("bin\tmp.*.ncch") do (
				set ARG=!ARG! -i "%%f:!i!:!i!"
				set /a i+=1
			)
			call :makeromCIA Game
			if "!golfEvent!"=="0" if /i "!TitleId!"=="0004000000042D00" call :golf
			if "!golfEvent!"=="0" if /i "!TitleId!"=="0004000000042B00" call :golf
			if "!golfEvent!"=="0" if /i "!TitleId!"=="0004000000181B00" call :golf
		)
		REM System Applications
		echo "!TitleId!" | findstr /i "00040010 0004001b 00040030 0004009b 000400db 00040130 00040138" >nul 2>&1
		if not errorlevel 1 (
			call :checkCIASysFile
			set CIAType=1
			echo | bin\decrypt.exe "!FileName!.cia" >nul 2>&1
			call :subroutineRename
			for %%f in ("bin\tmp.*.ncch") do (
				set ARG=!ARG! -i "%%f:!i!:!i!"
				set /a i+=1
			)
			call :makeromCIA System
		)
		REM Demos
		echo "!TitleId!" | findstr /i "00040002" >nul 2>&1
		if not errorlevel 1 (
			echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a demo title>>!logfile!
			set CIAType=1
			echo | bin\decrypt.exe "%%a" >nul 2>&1
			call :subroutineRename
			for %%f in ("bin\tmp.*.ncch") do (
				set ARG=!ARG! -i "%%f:!i!:!i!"
				set /a i+=1
			)
			call :makeromCIA Demo
		)
		REM Patches and DLCs
		echo "!TitleId!" | findstr /i /pr "0004000e 0004008c" >nul 2>&1
		if not errorlevel 1 (
			echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a update or DLC title>>!logfile!
			set CIAType=1
			set TEXT="ContentId:"
			set /a X=0
			echo | bin\decrypt.exe "!FileName!.cia" >nul 2>&1
			call :subroutineRename
			for %%f in ("bin\tmp.*.ncch") do (
				set ARG=!ARG! -i "%%f:!i!:!i!"
				set /a i+=1
			)
			for /f "delims=" %%d in ('findstr /c:!TEXT! !FILE!') do (
				set CONLINE=%%d
				call :EXF
			)
			REM Patches
			findstr /i /pr "0004000e" !FILE! | findstr /C:"Title id" >nul 2>&1
			if not errorlevel 1 (
				call :makeromCIA Patch
			)
			REM DLCs
			findstr /i /pr "0004008c" !FILE! | findstr /C:"Title id" >nul 2>&1
			if not errorlevel 1 (
				call :makeromCIA DLC
			)
		)
	)
	echo "!CryptoKey!" | findstr "None" >nul 2>&1
	if "!errorlevel!"=="0" (
		echo %date% - %time:~0,-3% = [^^^^] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is already decrypted>>!logfile!
		set /a CIAErrCount+=1
	) else (
		if not "!CIATYPE!"=="1" (
			REM TWL titles
			call :analyzeFileCIATWL
			if "!CryptoKey!"=="YES" (
				echo "!TitleId!" | findstr /i /pr "00048005 0004800f 00048004" >nul 2>&1
				if not errorlevel 1 (
					echo "!TitleId!" | findstr /i "00048005" >nul 2>&1
					if "!errorlevel!"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a TWL title [System Application]>>%logfile%
					echo "!TitleId!" | findstr /i "0004800f" >nul 2>&1
					if "!errorlevel!"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a TWL title [System Data Archive]>>%logfile%
					echo "!TitleId!" | findstr /i "00048004" >nul 2>&1
					if "!errorlevel!"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a TWL title [3DS DSiWare Ports]>>%logfile%
					bin\ctrtool.exe --contents=bin\00000000.app --meta=bin\00000000.app "!FileName!.cia" >nul 2>&1
					ren "bin\00000000.app.0000.00000000" "00000000.app" >nul 2>&1
					call :makeromTWL
				)
			) else (
				if "!CryptoKey!"=="NO" (
					echo %date% - %time:~0,-3% = [^^^^] TWL CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is already decrypted>>!logfile!
					set /a CIAErrCount+=1
				) else (
					if "!CIATYPE!"=="0" (
						echo %date% - %time:~0,-3% = [^^!] Could not determine CIA type [!FileName!.cia]>>!logfile!
						echo %date% - %time:~0,-3% = [^^!] Please report !TitleId! v!TitleVersion! to the developer>>!logfile!
					)
				)
			)
		)
	)
)
set /p ctrtool_data=<!content!
echo "!ctrtool_data!" | findstr "ERROR" >nul 2>&1
if "!errorlevel!"=="0" (
	echo %date% - %time:~0,-3% = [^^!] CIA is invalid [!FileName!.cia]>>!logfile!
	set /a CIAErrCount+=1
)
exit /b

:analyzeFileCIA
for /f "tokens=3 delims= " %%x in ('findstr /c:"Title id:" !content!') do set "TitleId=%%x"
for /f "tokens=3 delims= " %%z in ('findstr "TitleVersion" !content!') do set "TitleVersion=%%z"
for /f "delims=" %%y in ('findstr /c:"Crypto Key" !content!') do set "CryptoKey=%%y"
exit /b

:analyzeFileCIATWL
for /f "tokens=3 delims= " %%x in ('findstr /c:"TitleId:" !content!') do set "TitleId=%%x"
for /f "tokens=3 delims= " %%z in ('findstr "TitleVersion" !content!') do set "TitleVersion=%%z"
for /f "tokens=3 delims= " %%y in ('findstr /c:"Encrypted" !content!') do set "CryptoKey=%%y"
exit /b

:analyzeFile3DS
bin\ctrtool.exe --seeddb=bin\seeddb.bin "!fullFileName!" >!content!
set FILE=!content!
for /f "tokens=3 delims= " %%x in ('findstr /c:"Title id:" !content!') do set "TitleId=%%x"
for /f "tokens=2 delims= " %%z in ('findstr "TitleVersion" !content!') do set "TitleVersion=%%z"
for /f "delims=" %%y in ('findstr /c:"Crypto Key" !content!') do set "CryptoKey=%%y"
exit /b

:makeromCIA
echo %date% - %time:~0,-3% = [i] Calling makerom for %1 CIA [!TitleId! v!TitleVersion!]>>!logfile!
if "%1"=="DLC" (
	bin\makerom.exe -f cia -dlc -ignoresign -target p -o "!rootdir!\!FileName! %1-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>&1
) else (
	bin\makerom.exe -f cia -ignoresign -target p -o "!rootdir!\!FileName! %1-decrypted.cia"!ARG! -ver !TitleVersion! >nul 2>&1
)
if not exist "!FileName! %1-decrypted.cia" (
	echo %date% - %time:~0,-3% = [^^!] Decrypting failed [!TitleId! v!TitleVersion!]>>!logfile!
	set /a CIAErrCount+=1
) else (
	echo %date% - %time:~0,-3% = [i] Decrypting succeeded [!TitleId! v!TitleVersion!]>>!logfile!
	if "!convertToCCI!"=="0" set /a finalCount+=1
)
exit /b

:makeromTWL
echo %date% - %time:~0,-3% = [i] Calling makerom for TWL CIA [!TitleId! v!TitleVersion!]>>!logfile!
bin\makerom.exe -srl "bin\00000000.app" -f cia -ignoresign -target p -o "!rootdir!\!FileName! TWL-decrypted.cia" -ver !TitleVersion! >nul 2>&1
if exist "bin\00000000.app" del /F /Q "bin\00000000.app"
if not exist "!FileName! TWL-decrypted.cia" (
	echo %date% - %time:~0,-3% = [^^!] Decrypting failed [!TitleId! v!TitleVersion!]>>!logfile!
	set /a CIAErrCount+=1
) else (
	echo %date% - %time:~0,-3% = [i] Decrypting succeeded [!TitleId! v!TitleVersion!]>>!logfile!
	set /a finalCount+=1
)
exit /b

:convertToCCIFunction
echo "!TitleId!" | findstr /i /pr "000400db 0004001b 0004009b 00040010 00040030 00040130 0004000e 0004008c 00048005 0004800f 00048004 00040002" >nul 2>&1
if "!errorlevel!"=="0" (
	if exist "!FileName!*-decrypted.cia" del /F /Q "!FileName!*-decrypted.cia"
	echo %date% - %time:~0,-3% = [^^!] Converting to CCI for this title ist not supported [!TitleId! v!TitleVersion!]>>!logfile!
	set /a CCIErrCount+=1
) else (
	for %%a in ("!FileName!*-decrypted.cia") do (
		set FileName=%%~na
		bin\makerom.exe -ciatocci "!FileName!.cia" -o "!FileName!.cci" >nul 2>&1
		if not exist "!FileName!.cci" (
			echo %date% - %time:~0,-3% = [^^!] Converting to CCI failed [!FileName!.cia]>>!logfile!
			if exist "!FileName!*-decrypted.cia" del /F /Q "!FileName!*-decrypted.cia"
			set /a CCIErrCount+=1
		) else (
			del /F /Q "!FileName!.cia"
			echo %date% - %time:~0,-3% = [i] Converting to CCI succeeded [!FileName!.cci]>>!logfile!
			set /a finalCount+=1
		)
	)
)
exit /b

:validate
if not defined oldname goto :eof
set "c1=%oldname:~0,1%"
set "oldname=%oldname:~1%"
if "!validchars:%c1%=!" neq "%validchars%" set "newname=%newname%%c1%"
goto validate

:FilesDecrypted
cls
echo:
call :ReduxBanner
echo:
echo:
echo   Decrypting finished^^!
echo:
call :ReduxSummary
echo:
echo   Please review "!logfile!" for more details.
echo:
echo %date% - %time:~0,-3% = [i] Decrypting process succeeded>>!logfile!
echo %date% - %time:~0,-3% = [i] Script execution ended>>!logfile!
endlocal
pause >nul | echo Press any key to exit . . .
exit

:noFilesDecrypted
cls
echo:
call :ReduxBanner
echo:
echo:
echo   No files were decrypted^^!
echo:
echo   Please review "!logfile!" for more details.
echo:
echo %date% - %time:~0,-3% = [^^] No files where decrypted>>!logfile!
echo %date% - %time:~0,-3% = [i] Script execution ended>>!logfile!
pause >nul | echo Press any key to exit . . .
exit

:noFilesFound
cls
echo:
call :ReduxBanner
echo:
echo:
echo   No CIA or 3DS files found^^!
echo:
echo   Please review "!logfile!" for more details.
echo:
echo %date% - %time:~0,-3% = [^^] No CIA or 3DS were found>>!logfile!
echo %date% - %time:~0,-3% = [i] Script execution ended>>!logfile!
pause >nul | echo Press any key to exit . . .
exit

:someFilesDecrypted
cls
echo:
call :ReduxBanner
echo:
echo:
echo   Some files were not decrypted^^!
echo:
call :ReduxSummary
echo:
echo   Please review "!logfile!" for more details.
echo:
echo %date% - %time:~0,-3% = [^^] Some files where not decrypted>>!logfile!
echo %date% - %time:~0,-3% = [i] Script execution ended>>!logfile!
pause >nul | echo Press any key to exit . . .
exit

:unsupported
cls
echo:
call :ReduxBanner
echo:
echo:
echo   The current operating system is incompatible.
echo   Please run the script on the following systems:
echo:
echo   - Windows 7 SP1 [x64] or higher
echo   - Windows Server 2008 R2 SP1 [x64] or higher
echo:
echo   Script execution halted^^!
echo:
echo %date% - %time:~0,-3% = [^!] 32-bit operating systems are not supported>>!logfile!
echo %date% - %time:~0,-3% = [i] Script execution ended>>!logfile!
pause >nul | echo Press any key to exit . . .
exit

:checkCIASysFile
echo "!TitleId!" | findstr /i "00040010" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a system application>>%logfile%
echo "!TitleId!" | findstr /i /pr "0004001b 000400db" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a system data archive>>%logfile%
echo "!TitleId!" | findstr /i "00040030" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a system applet>>%logfile%
echo "!TitleId!" | findstr /i "0004009b" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a shared data archive>>%logfile%
echo "!TitleId!" | findstr /i "00040130" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a system module>>%logfile%
echo "!TitleId!" | findstr /i "00040138" >nul 2>&1
if "%errorlevel%"=="0" echo %date% - %time:~0,-3% = [i] CIA file "!FileName!.cia" [!TitleId! v!TitleVersion!] is a system firmware>>%logfile%
exit /b

:checkForCCIFile
if "!convertToCCI!"=="0" (
	echo %date% - %time:~0,-3% = [^^^^] CIA file "!FileName!.cia" was already decrypted>>!logfile!
	set /a finalCount+=1
) else (
	if not exist "!FileName!*-decrypted.cci" (
		call :convertToCCIFunction
	) else (
		echo %date% - %time:~0,-3% = [^^^^] CIA file "!FileName!.cia" was already converted into CCI>>!logfile!
		set /a finalCount+=1
	)
)
exit /b

:ReduxBanner
echo   ############################################################
echo   ###                                                      ###
if "!VersionExtended!"=="0" (
	echo   ###         Batch CIA 3DS Decryptor Redux %ScriptVersion%         ###
) else (
	echo   ###        Batch CIA 3DS Decryptor Redux %ScriptVersion%        ###
)
echo   ###                                                      ###
echo   ############################################################
REM echo   !count3DS! !countCIA! - !DSErrCount! !CCIErrCount! !CIAErrCount! - !totalCount! !finalCount!
exit /b

:ReduxSummary
echo   Summary:
if !count3DS! GEQ 1 (
	if !DSErrCount! GEQ 1 (
		echo   - !DSErrCount! from !count3DS! 3DS file[s] were not decrypted
	) else (
		echo   - !count3DS! from !count3DS! 3DS file[s] decrypted
	)
)
if "!convertToCCI!"=="1" (
	if !CCIErrCount! GEQ 1 (
		echo   - !CCIErrCount! from !countCIA! CIA file[s] were not decrypted into CCI
	) else (
		echo   - !countCIA! from !countCIA! CIA file[s] decrypted into CCI
	)
) else (
	if !countCIA! GEQ 1 (
		if !CIAErrCount! GEQ 1 (
			echo   - !CIAErrCount! from !countCIA! CIA file[s] were not decrypted
		) else (
			echo   - !countCIA! from !countCIA! CIA file[s] decrypted
		)
	)
)
exit /b

:golf
cls
echo:
call :ReduxBanner
echo:
echo:
echo            ######      ######    ##          ##########
echo          ##########  ##########  ##          ##########
echo          ##      ##  ##      ##  ##          ##
echo          ##          ##      ##  ##          ########
echo          ##    ####  ##      ##  ##          ########
echo          ##      ##  ##      ##  ##          ##
echo          ##########  ##########  ##########  ##
echo            ########    ######    ##########  ##
echo:
echo:
echo        On my business card, I am a corporate president.
echo        In my mind, I am a computer programmer. But in my
echo        heart, I am a gamer. - Satoru Iwata [1959 - 2015]
echo:
timeout /t 6 >nul
set golfEvent=1
cls
echo:
call :ReduxBanner
echo:
echo:
echo   Decrypting...
set FancyArt=0
call :ReduxFancyArt
exit /b

:ReduxFancyArt
echo:
echo:
echo:
echo                  #############   #############
echo                  #         ###   #         ###
if !countCIA! GEQ 1 if !count3DS! GEQ 1 (
	echo                  # CIA/3DS #     # CIA/CCI #
	set FancyArt=1
)
if "!convertToCCI!"=="1" (
	if not "!FancyArt!"=="1" if !countCIA! GEQ 1 (
		echo                  #   CIA   #     #   CCI   #
		set FancyArt=1
	)
) else (
	if not "!FancyArt!"=="1" if !countCIA! GEQ 1 (
		echo                  #   CIA   #     #   CIA   #
		set FancyArt=1
	)
)
if not "!FancyArt!"=="1" if !count3DS! GEQ 1 (
	echo                  #   3DS   #     #   CCI   #
)
echo                  #        --------^>        #
echo                  #         #     #         #
echo                  ###########     ###########
exit /b
@echo off

:background
	rem
	rem Provide user with background information about prepnewpc.cmd
	rem
	echo How and Why To Use PREPNEWPC in Steadier State
	pause

:setup
	rem
	rem Check that we're running from the root of the boot device
	rem Use the pseudo-variable ~d0 to get the job done
	rem _actdrive = the currently active drive
	rem
	setlocal enabledelayedexpansion
	set "_strletters=C D E F G H I J K L M N O P Q R S T U V W Y Z"
	set _actdrive=%~d0
	if not '%_actdrive%'=='X:' goto :notwinpe
	%_actdrive%
	cd \
	if not exist %_actdrive%\windows\system32\Dism.exe (
		echo.
		goto :notwinpe
	)

:bioscheck
	rem
	rem Use wpeutil and reg to find out if PE was booted using bios/uefi
	rem
	wpeutil UpdateBootInfo
	for /f "tokens=3" %%a in ('reg query HKLM\System\CurrentControlSet\Control /v PEFirmwareType') do (set _firmware=%%a)
	if '%_firmware%'=='' (
		echo.
		goto :badend
	)
	if '%_firmware%'=='0x1' (
		echo The PC is booted in BIOS mode.
		set _firmware=bios
		set _winload=\windows\system32\boot\winload.exe
	)
	if '%_firmware%'=='0x2' (
		echo The PC is booted in UEFI mode.
		set _firmware=uefi
		set _winload=\windows\system32\boot\winload.efi
	)

:extdrivequestion
	rem
	rem _extdrive = external drive letter where we'll write the wim and then vhd (should include colon)
	rem
	echo.
	for /f "delims={}" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (echo %%a)
	echo.
	set /p _extdrive=What is your response? 
	if '%_extdrive%'=='end' goto :end
	if '%_extdrive%'=='' (
		echo.
		goto :extdrivequestion
	)
	if not exist %_extdrive%\scratch md %_extdrive%\scratch

:warnings
	rem
	rem Warn about data loss and give outline of the remaining steps
	rem
	cls
	echo ===============================================================
	pause
	cls
	echo After wiping disk 0, it will install a 2GB Windows boot
	if %_firmware%==uefi (
		echo Next, we will create a 200MB uefi partition, that will contain
	)
	echo Finally, this takes the remaining disk space and creates one
	set /p _wiperesponse=Please type the word in lowercase and press Enter. 
	echo.
	if not %_wiperesponse%==wipe goto :goodend

:findusbdrive
	rem
	rem Next, find the USB drive's "real" drive letter
	rem (The USB or DVD boots from a drive letter like C: or
	rem the like, mounting and expanding a single file named
	rem boot.wim into an X: drive.  As I want to image WinPE
	rem onto the hard disk, I need access to non-expanded
	rem version of the \sources\boot.wim image.  This tries to
	rem find that by using diskpart to check the volume label
	rem _usbdrive = The USB drive's "real" drive letter
	rem listvolume.txt = The script to find the volumes
	rem
	echo.
	for /f "tokens=3,4" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (if %%b==WINPE set _usbdrive=%%a:)
	set _usbdriverc=%errorlevel%
	if '%_usbdrive%'=='' (
		echo.
		goto :badend
	)
	if %_usbdriverc%==0 (
		echo.
		goto :findbootwim
	)
	echo.
	goto :badend

:findbootwim
	rem
	rem Check if boot.wim exists
	rem
	echo.
	if exist %_usbdrive%\sources\boot.wim (
		echo.
		goto :findsrsdrive
	)
	echo.
	goto :badend

:findsrsdrive
	rem
	rem Find an available drive letter for the Steadier State Tools Partition
	rem srsdrive = Partition for the Steadier State Tools (SrS tools)
	rem
	echo.
	for /f "tokens=3" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (
		set _volletter=%%a
		set _volletter=!_volletter:~0,1!
		call set _strletters=%%_strletters:!_volletter! =%%
	)
	for %%a in (%_strletters%) do (
		if not exist %%a:\ (
			echo.
			set _srsdrive=%%a
			goto :makesrsdrive
		)
	)
	echo.
	goto :badend

:makesrsdrive
	rem
	rem Create SrS tools partition
	rem
	echo.
set /p _disknum=Disk Number: 
echo select disk %_disknum% >%_actdrive%\makesrs.txt
	if %_firmware%==uefi echo convert gpt >>%_actdrive%\makesrs.txt
	echo create partition primary size=2000 >>%_actdrive%\makesrs.txt
	if %_firmware%==bios echo active >>%_actdrive%\makesrs.txt
	echo assign letter=%_srsdrive% >>%_actdrive%\makesrs.txt
	if %_firmware%==uefi echo set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac" >>%_actdrive%\makesrs.txt
	if %_firmware%==uefi echo gpt attributes=0x8000000000000001 >>%_actdrive%\makesrs.txt
	echo rescan >>%_actdrive%\makesrs.txt
	diskpart /s %_actdrive%\makesrs.txt
	set _makesrsrc=%errorlevel%
	if %_makesrsrc%==0 (
		echo.
		set _srsdrive=%_srsdrive%:
		if %_firmware%==uefi (
			goto :findefidrive
		) else (
			goto :findphydrive
		)
	)
	echo.
	goto :badend

:findefidrive
	rem
	rem Find an available drive letter for the System Partition
	rem _efidrive = System Partition for uefi boot
	rem
	echo.
	for /f "tokens=3" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (
		set _volletter=%%a
		set _volletter=!_volletter:~0,1!
		call set _strletters=%%_strletters:!_volletter! =%%
	)
	for %%a in (%_strletters%) do (
		if not exist %%a:\ (
			echo.
			set _efidrive=%%a
			goto :makeefidrive
		)
	)
	echo.
	goto :badend

:makeefidrive
	rem
	rem Create System_UEFI partition
	rem
	echo.
set /p _disknum=Disk Number: 
echo select disk %_disknum% >%_actdrive%\makesrs.txt
	diskpart /s %_actdrive%\makeefi.txt
	set _makeefirc=%errorlevel%
	if %_makeefirc%==0 (
		echo.
		set _efidrive=%_efidrive%:
		goto :makemsrdrive
	)
	echo.
	goto :badend

:makemsrdrive
	rem
	rem Create Microsoft Reserved (MSR) partition
	rem
	echo.
set /p _disknum=Disk Number: 
echo select disk %_disknum% >%_actdrive%\makesrs.txt
	diskpart /s %_actdrive%\makemsr.txt
	set _makemsrrc=%errorlevel%
	if %_makemsrrc%==0 (
		echo.
		goto :findphydrive
	)
	echo.
	goto :badend

:findphydrive
	rem
	rem Find an available drive letter for the remaining space on the Hard Drive
	rem _phydrive = Physical Drive Partition
	rem
	echo.
	for /f "tokens=3" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (
		set _volletter=%%a
		set _volletter=!_volletter:~0,1!
		call set _strletters=%%_strletters:!_volletter! =%%
	)
	for %%a in (%_strletters%) do (
		if not exist %%a:\ (
			echo.
			set _phydrive=%%a
			goto :makephydrive
		)
	)
	echo.
	goto :badend

:makephydrive
	rem
	rem Create Physical Drive partition
	rem
	echo.
set /p _disknum=Disk Number: 
echo select disk %_disknum% >%_actdrive%\makesrs.txt
	diskpart /s %_actdrive%\makephy.txt
	set _makephyrc=%errorlevel%
	if %_makephyrc%==0 (
		echo.
		set _phydrive=%_phydrive%:
		goto :applywim
	)
	echo.
	goto :badend

:applywim
	rem
	rem Apply the boot.wim from the PE drive to the %_srsdrive%
	rem
	echo.
	Dism /ScratchDir:%_extdrive%\scratch /Apply-Image /ImageFile:%_usbdrive%\sources\boot.wim /ApplyDir:%_srsdrive% /Index:1 /CheckIntegrity /Verify
	set _applyrc=%errorlevel%
	if %_applyrc%==0 (
		echo.
		goto :findvhddrive
	)
	echo.
	goto :badend

:findvhddrive
	rem
	rem Find an available drive letter that can be used to mount the image.vhd
	rem _vhddrive = The drive letter used to mount image.vhd
	rem
	echo.
	for /f "tokens=3" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (
		set _volletter=%%a
		set _volletter=!_volletter:~0,1!
		call set _strletters=%%_strletters:!_volletter! =%%
	)
	for %%a in (%_strletters%) do (
		if not exist %%a:\ (
			echo.
			set _vhddrive=%%a
			goto :copyvhd
		)
	)
	echo.
	goto :badend

:copyvhd
	rem
	rem Copy the vhd on to the %_phydrive% drive
	rem
	echo.
	robocopy %_extdrive% %_phydrive% image.vhd /mt:50
	set _copyvhdrc=%errorlevel%
	if %_copyvhdrc%==1 (
		echo.
		goto :attachvhd
	)
	echo.
	goto :badend

:attachvhd
	rem
	rem attachvhd.txt is the name of the script attach the vhd
	rem
	echo.
	diskpart /s %_actdrive%\attachvhd.txt
	set _attachvhdrc=%errorlevel%
	if %_attachvhdrc%==0 (
		echo.
		goto :listvolume
	)
	echo.
	goto :badend

:listvolume
	rem
	rem listvolume.txt is the name of the script to find the volumes
	rem
	echo.
	for /f "tokens=2,4" %%a in ('diskpart /s %_actdrive%\srs\listvolume.txt') do (if %%b==Windows_SrS set _volnum=%%a)
	set _volnumrc=%errorlevel%
	if '%_volnum%'=='' (
		echo.
		goto :badend
	)
	if %_volnumrc%==0 (
		echo.
		goto :mountvhd
	)
	echo.
	goto :badend

:mountvhd
	rem
	rem mountvhd.txt is the name of the script to assign the drive letter
	rem
	echo.
	diskpart /s %_actdrive%\mountvhd.txt
	set _mountvhdrc=%errorlevel%
	if %_mountvhdrc%==0 (
		echo.
		set _vhddrive=%_vhddrive%:
		goto :copybcd
	)
	echo.
	goto :badend

:copybcd
	rem
	rem Grab a basic boot folder and BOOTMGR
	rem
	echo.
	if %_firmware%==bios (
		set _bcdstore=/store %_srsdrive%\Boot\BCD
		bcdboot %_vhddrive%\windows /s %_srsdrive% /f ALL
	)
	if %_firmware%==uefi (
		set _bcdstore=/store %_efidrive%\EFI\Microsoft\Boot\BCD
		bcdboot %_vhddrive%\windows /s %_efidrive% /f ALL
	)
	set _bcdbootrc=%errorlevel%
	if %_bcdbootrc%==0 (
		echo.
		goto :bcdconfig
	)
	echo.
	goto :badend

:bcdconfig
	rem
	rem Modify the BCD to support Steadier State
	rem
echo.
	for /f "tokens=2 delims={}" %%a in ('bcdedit %_bcdstore% /create /d "Roll Back Windows" /application osloader') do (set _guid={%%a})
	@echo off
	if '%_guid%'=='' (
		echo.
		goto :badend
	)
	echo on
	bcdedit %_bcdstore% /set %_guid% osdevice partition=%_srsdrive%
	bcdedit %_bcdstore% /set %_guid% device partition=%_srsdrive%
	bcdedit %_bcdstore% /set %_guid% path %_winload%
	bcdedit %_bcdstore% /set %_guid% systemroot \windows
	bcdedit %_bcdstore% /set %_guid% winpe yes
	bcdedit %_bcdstore% /set %_guid% detecthal yes
	bcdedit %_bcdstore% /displayorder %_guid% /addlast
	bcdedit %_bcdstore% /timeout 1
	@echo off
	for /f "delims=" %%a in ('bcdedit %_bcdstore% /enum /v') do (
		for /f "tokens=1,2" %%b in ('echo %%a') do (
			if %%b==identifier (
				set _guid=%%c
				bcdedit %_bcdstore% /enum !_guid! /v | find /c "image.vhd" >%_actdrive%\temp.txt
				set _total=
				set /p _total= <%_actdrive%\temp.txt
				del %_actdrive%\temp.txt 2>nul
				if not !_total!==0 (
						bcdedit %_bcdstore% /default !_guid!
						echo Successfully set image.vhd as default, reboot and you're ready to go.
						goto :copysrs
				)
			)
		)
	)
	echo.
	goto :badend

:copysrs
	rem
	rem copy over the Steadier State files from the USB/DVD
	rem
	echo.
	robocopy %_actdrive%\srs %_srsdrive%\srs
	rem
	rem and the updated startnet.cmd
	rem
	copy %_actdrive%\startnethd.cmd %_srsdrive%\windows\system32\startnet.cmd /y
	copy %_actdrive%\windows\system32\Dism.exe %_srsdrive%\windows\system32 /y
	rem
	rem and the necessary files for the vhd
	rem
	md %_vhddrive%\srs
	copy %_actdrive%\srs\bcddefault.cmd %_vhddrive%\srs /y
	copy %_actdrive%\srs\firstrun.cmd %_vhddrive%\srs /y
	copy %_actdrive%\srs\listvolume.txt %_vhddrive%\srs\listvolume.txt
	md %_vhddrive%\srs\hooks
	copy %_actdrive%\srs\hooks\* %_vhddrive%\srs\hooks /y
	md %_vhddrive%\srs\hooks-samples
	copy %_actdrive%\srs\hooks-samples\* %_vhddrive%\srs\hooks-samples /y
	goto :goodend

:notwinpe
	rem
	rem prepnewpc.cmd was not run from a PE
	rem
	echo.
	goto :end

:goodend
	rem
	rem Success
	rem
	echo.

echo ===============================================================
	goto :end

:badend
	rem
	rem Something failed
	rem
	echo.

:end
	rem
	rem Final message before exiting
	rem
	endlocal
	echo.

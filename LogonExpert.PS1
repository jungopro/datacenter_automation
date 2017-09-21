<#
.SYNOPSIS
  Deploy Logon Expert Software

.DESCRIPTION
  This script will deploy LogonExpert software to all computers in the Host_Name.txt text file
  
.INPUTS
  You must have the following folder preset \\storage\logonexpert
  You must have the following 3 files present in the folder:
  - LogonExpertSetup.exe    -   Setup Installer for LogonExpert
  - LogonExpertKey.lic      -   Valid License file for LogonExpert
  - Host_Names.txt          -   TXT file with a list of all the computers you want to deploy LogonExpert to

.OUTPUTS
  Outputs will be written to the logfile defined in the $logfile parameter

.NOTES
  Version:        1.1
  Author:         Omer Barel
  Creation Date:  December 13th, 2016
  Purpose/Change: Added logging functionality
  
.EXAMPLE
  Logonexpert.ps1
#>

#-----------------------------------------------------------[Parameters]------------------------------------------------------------
$computers = Get-Content "\\storage\Logonexpert\Host_Names.txt"
$installpath = "\\storage\Logonexpert\LogonExpertSetup.exe"
$parameters = "/verysilent /norestart"
$packageinstall=(split-path $installpath -leaf) + ' ' + $parameters
$licpath = "\\storage\Logonexpert\LogonExpertKey.lic"
$logfile = "\\storage\LogonExpert.log"

#-----------------------------------------------------------[Execution]------------------------------------------------------------
$InstallTime = get-date
Write-Output "$InstallTime --- LogonExpert will be installed on the following computers: $computers" >> $logfile

$computers | Where-Object {test-connection $_ -quiet -count 1} | ForEach-Object {
    Write-Output "====================================================================================" >> $logfile
	$InstallTime = get-date
    Write-Output "$InstallTime --- Starting LogonExpert Installation on Computer $_" >> $logfile
	Write-Output "$InstallTime --- Creating temp install directory on Computer $_" >> $logfile
    New-Item -Type Directory -Path \\$_\c$\LogonExpert
    $InstallTime = get-date
    Write-Output "$InstallTime --- Copying Installation files to Computer $_" >> $logfile
    Copy-Item $installpath \\$_\c$\Logonexpert
    Copy-Item $licpath \\$_\c$\LogonExpert
    $InstallTime = get-date
    Write-Output "$InstallTime --- Installing LogonExpert on Computer $_" >> $logfile
    $newProc=([WMICLASS]"\\$_\root\cimv2:win32_Process").Create("C:\Logonexpert\$packageinstall")
    Write-Host "Checking Connectivity...Setup will continue in 10 seconds"
    Invoke-Command -ComputerName $_ { ping localhost -n 10>nul}
    $InstallTime = get-date
    Write-Output "$InstallTime --- Configuring LogonExpert on Computer $_" >> $logfile
    Invoke-Command -ComputerName $_ -ScriptBlock { & cmd.exe /c "C:\Program Files\Softros Systems\LogonExpert\le.exe" /setcredentials user password! domain.local }
    $InstallTime = get-date
    Write-Output "$InstallTime --- Rebooting Computer $_" >> $logfile
    Invoke-Command -ComputerName $_ -ScriptBlock {shutdown -r -t 060}
    $InstallTime = get-date
    Write-Output "$InstallTime --- Removing temp folder from Computer $_" >> $logfile
    Remove-Item -Path "\\$_\c$\logonexpert" -Recurse
    $InstallTime = get-date
    Write-Output "$InstallTime --- Installation on Computer $_ completed succsessfully. Please verify user is logged in automatically after the reboot" >> $logfile
}

Write-Output "====================================================================================" >> $logfile
Write-Host "Installation finished for the following computers: $computers. Please review $logfile for full details"
<#
    .SYNOPSIS
      Configure HP Bios Settings

    .DESCRIPTION
      This script will take IP parameters from .CSV file and configure various BIOS options on HP DL Server (Gen9)
      You must configure iLO IP and all servers must have the same iLO Admin credentials
      Servers must be turned off before running the script

    .INPUTS
      \\storage\Bios.csv

    .OUTPUTS
      Log file will be created \\storage\Bios_Configuration.log

    .NOTES
      Version:        1.0
      Author:         Omer Barel
      Creation Date:  February 23rd, 2017
      Purpose/Change: Production Version
      Todo:           Add write-log functionality
    
    .EXAMPLE
      Bios.ps1
#>

#----------------------------------------------------------[Parameters]----------------------------------------------------------

$iLOCred = Get-Credential -Message "Please enter iLO Admin Credentials"
$Servers = Import-Csv -Path "\\storage\Bios.csv"
$logfile = "\\storage\Bios_Configuration.log"

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Confirm:$false -Force

foreach ($Server in $Servers) {
    $InstallTime = get-date
    write-output "=====================================================================================" >> $logfile
    $TempIP = $Server.iLOIP
    write-output "$InstallTime --- Configuring Server with iLO IP $TempIP" >> $logfile
    $iLOConnection = Connect-HPBIOS -Credential $iLOCred -IP $Server.iLOIP -DisableCertificateAuthentication -Force # Connect
	write-output "$InstallTime --- Reseting iLO Configuration and rebooting. Script will continue in 7 minutes" >> $logfile
    Reset-HPBIOSDefaultManufacturingSetting -Connection $iLOConnection -ResetDefaultManufacturingSetting # Reset BIOS to default
	Set-HPiLOHostPower -Server $Server.iLOIP -Credential $iLOCred -HostPower On -DisableCertificateAuthentication # Shutdown
    
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "Please wait 7 mintues for server to reset BIOS config and reboot"
    Start-Sleep -Seconds 420

	# Set UEFI
	write-output "$InstallTime --- Setting BIOS to UEFI Mode" >> $logfile
    Set-HPBIOSBootMode -Connection $iLOConnection -BootMode UEFI_Mode

	# Enable UEFI Optimized boot
    write-output "$InstallTime --- Enabling Optimized UEFI Boot" >> $logfile
	Set-HPBIOSUEFIOptimizedBoot -Connection $iLOConnection -UEFIOptimizedBoot Enabled

	# Set boot policy
    write-output "$InstallTime --- Configuring Boot Policy" >> $logfile
	Set-HPBIOSBootOrderPolicy -Connection $iLOConnection -BootOrderPolicy Retry_Indefinitely
	Set-HPBIOSNetworkBootOption -Connection $iLOConnection -UEFIPXEBootPolicy IPv4 -PreBootNetworkInterface EmbeddedFlexLOM1
	Set-HPBIOSUEFIBootOrder -Connection $iLOConnection -UEFIBootOrder "2,3" # (2=Raid, 3=10GB IPv4)

	# Stay off after power failure
    write-output "$InstallTime --- Configuring Power Policy" >> $logfile
	Set-HPBIOSServerAvailability -Connection $iLOConnection -ASR Disabled -AutomaticPowerOn Always_Remain_Off

	# Enable Virtualization
    write-output "$InstallTime --- Configuring Virtualization Options" >> $logfile
	Set-HPBIOSVirtualization -Connection $iLOConnection -CPU_Virtualization Enabled -Intel_VT_d2 Enabled -SR_IOV Enabled

    # NUMA Configuration
    write-output "$InstallTime --- Configuring NUMA" >> $logfile
	Set-HPBIOSAdvancedPerformanceTuningOption -Connection $iLOConnection -NUMAGroupSizeOptimization $Server.Numa

	# NodeInterleaving Configuration
    write-output "$InstallTime --- Configuring Node Interleaving" >> $logfile
	Set-HPBIOSNodeInterleaving -Connection $iLOConnection -NodeInterleaving $Server.NodeInterleaving

	# HyperThreading Configuration
    write-output "$InstallTime --- Configuring HyoerThreading" >> $logfile
	Set-HPBIOSProcessorOption -Connection $iLOConnection -IntelHyperthreading $Server.HyperThreading

	# Disconnect
    write-output "$InstallTime --- Closing BIOS Connection" >> $logfile
	Disconnect-HPBIOS -Connection $iLOConnection
    write-output "$InstallTime --- Rebooting the server to apply configuration" >> $logfile
    Reset-HPiLOServer -Server $Server.iLOIP -Credential $iLOCred -DisableCertificateAuthentication
}
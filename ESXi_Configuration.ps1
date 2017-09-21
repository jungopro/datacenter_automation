<#
    .SYNOPSIS
      Configures a new ESXi host
    
    .DESCRIPTION
      This script will configure various parameters on a given ESXi host. For best results, run this script immidiatley after you finish    installing the ESXi host.
    
    .PARAMETER vCenter
        Enter the FQDN of the vCenter Server you want to connect to
    
    .PARAMETER ESXiHostIP
        Enter the IP for the ESXi
    
    .PARAMETER ESXiHostname
        Enter the short hostname (not FQDN) for the ESXi
    
    .PARAMETER ESXiLicense
        Enter the ESXi license key
    
    .PARAMETER Datacenter
        Enter the Location the ESXi should reside in - Cluster, Datacenter, etc.
    
    .PARAMETER DNSZone
        Enter the DNS Zone name the ESXi should reside in
    
    .INPUTS
      Parametrs as stated above
    
    .OUTPUTS
      None.
    
    .NOTES
      Version:        1.0
      Author:         Omer Barel
      Creation Date:  February 14, 2017
      Purpose/Change: Stable Version
    
    .EXAMPLE
      ESXi_Configuration.ps1 -vCenter vcenter.domain.local -ESXiHostIP 192.168.120.8 -ESXiHostname ESXi-05 -ESXiLicense    XXXXX-XXXXX-XXXXX-XXXXX-XXXXX -Datacenter DC -DNSZone domain.local
#>

#----------------------------------------------------------[Parameters]----------------------------------------------------------

[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,HelpMessage="Enter the FQDN of the vCenter Server you want to connect to")]
   [string]$vCenter,

   [Parameter(Mandatory=$True,HelpMessage="Enter the IP for the ESXi")]
   [string]$ESXiHostIP,
	
   [Parameter(Mandatory=$True,HelpMessage="Enter the short hostname (not FQDN) for the ESXi")]
   [string]$ESXiHostname,

   [Parameter(Mandatory=$false,HelpMessage="Enter the ESXi license key")]
   [string]$ESXiLicense,

   [Parameter(Mandatory=$True,HelpMessage="Enter the Location the ESXi should reside in - Cluster, Datacenter, etc.")]
   [string]$Datacenter,

   [Parameter(Mandatory=$True,HelpMessage="Enter the DNS Zone name the ESXi should reside in")]
   [string]$DNSZone
)

#----------------------------------------------------------[Functions and Prerequisites]----------------------------------------------------------

function Import-PowerCLI {
    Import-Module VMware.VimAutomation.Cis.Core
    Import-Module VMware.VimAutomation.Cloud
    Import-Module VMware.VimAutomation.Common
    Import-Module VMware.VimAutomation.Core
    Import-Module VMware.VimAutomation.HA
    Import-Module VMware.VimAutomation.License
    Import-Module VMware.VimAutomation.PCloud
    Import-Module VMware.VimAutomation.SDK
    Import-Module VMware.VimAutomation.Storage
    Import-Module VMware.VimAutomation.Vds
    Import-Module VMware.VimAutomation.vROps
    Import-Module VMware.VumAutomation
}

Write-Host -ForegroundColor Black -BackgroundColor Yellow "Loading VMware automation modules. Please wait..."

# Import VMware PowerCLI modules
Import-PowerCLI

# Retrieve vCenter Admin user Credentials
$DomainAdminCred=Get-Credential -Message "Please Enter the credentials for a Domain Admin User in the form of user@domain.fqdn"

# Retrieve ESXi root user Credentials
$ESXHostCredentials=Get-Credential -Message "Please Enter the credentials for the ESXi root user"

# Get current date & time
$Starttime = Get-Date

# Define the ESXi Specific Parameters
$ESXiFQDN=$ESXiHostname+"."+$DNSZone
$ESXiDS_Name=$ESXiHostname+"_DS"

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Rename the ESXi Host
Connect-VIServer -Server $ESXiHostIP -Credential $ESXHostCredentials
$ESXiCli = Get-EsxCli -VMHost $ESXiHostIP
$ESXiCli.system.hostname.set($null,$ESXiHostname,$null)
Disconnect-VIServer -Server $ESXiHostIP -Confirm:$false

# Add A record to DNS
Add-DnsServerResourceRecordA -Name $ESXiHostname -ZoneName $DNSZone -IPv4Address $ESXiHostIP -ComputerName DC-01

# Connect to the vCenter
Connect-VIServer -Server $vCenter -Credential $DomainAdminCred 

# Add the ESXi to the vCenter
Add-VMHost -Name $ESXiFQDN -Location $Datacenter -Credential $ESXHostCredentials -force 
Start-Sleep -Seconds 15 #wait...

#License the ESX
Set-VMHost -VMHost $ESXiFQDN -LicenseKey $ESXiLicense

# Configure Datastore

Get-Datastore -VMHost $ESXiFQDN | Set-Datastore -Name $ESXiDS_Name

# Configure Networking
Get-VMHost -Name $ESXiFQDN | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Mtu 9000 -Confirm:$false
Get-VMHost -Name $ESXiFQDN | Get-VirtualSwitch | Set-VirtualSwitch -Mtu 9000 -Confirm:$false
Start-Sleep -Seconds 15

# Configure NTP
Add-VMHostNtpServer -VMHost $ESXiFQDN -NtpServer "dc-01.domain.local","dc-02.domain.local"
Get-VMHostFirewallException -VMHost $ESXiFQDN | Where-Object {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
Get-VMHostService -VMHost $ESXiFQDN | Where-Object {$_.Key -eq "ntpd"} | Start-VMHostService
Get-VMHostService -VMHost $ESXiFQDN | Where-Object {$_.Key -eq "ntpd"} | Set-VMHostService -Policy On

# Configure SSH
Get-VMHostFirewallException -VMHost $ESXiFQDN | Where-Object {$_.Name -eq "SSH Server"} | Set-VMHostFirewallException -Enabled:$true
Get-VMHostService -VMHost $ESXiFQDN | Where-Object {$_.Key -eq "TSM-SSH"} | Start-VMHostService
Get-VMHostService -VMHost $ESXiFQDN | Where-Object {$_.Key -eq "TSM-SSH"} | Set-VMHostService -Policy On
Get-AdvancedSetting -Entity $ESXiFQDN | Where-Object {$_.Name -eq "UserVars.SuppressShellWarning"} | Set-AdvancedSetting -Value "1" -Confirm:$false

Write-Host -ForegroundColor Black -BackgroundColor Yellow "Rebooting ESXi host to complete installation. Please configure Passthrough and Import VMs"

# Reboot Host to finalize setup
Restart-VMHost -VMHost $ESXiFQDN -Confirm:$false -Force
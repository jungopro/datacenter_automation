# Define Environment Specific Parameters

$Datacenter = "DC" #Name of the Datacenter as you'd like
$ESXHosts =  Get-Content "C:\Temp\ESXiHosts.csv"
Write-Host 'Please Enter Credentials for ESXi Login'
$ESXCred = Get-Credential -Message "Please Enter Credentials for ESXi Root User" -UserName "root"
$Location = get-folder -norecursion
$vCenterKey = Get-Content "C:\Temp\vCenterKey.txt"
$vSphereKey = Get-Content "C:\Temp\vSphereKey.txt"
$VMs = import-csv -Path "C:\Temp\VMs.csv"

# Add Powershell Prerequisites

Add-WindowsFeature -Name RSAT -IncludeAllSubFeature
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

# Connect to the vCenter

Connect-VIServer "vcenter.domain.local"

# Create New Datacenter
New-Datacenter -Location $Location -Name $Datacenter

# License the vCenter

$MyVC = Connect-VIServer "vcenter.domain.local"
$LicenseManager = Get-View ($MyVC.ExtensionData.Content.LicenseManager)
$LicenseManager.AddLicense($vCenterKey,$Null)
$LicenseAssignmentManager = Get-View ($LicenseManager.LicenseAssignmentManager)
$LicenseAssignmentManager.UpdateAssignedLicense($MyVC.InstanceUuid,$vCenterKey,$Null)

# Configure ESXi Servers

foreach ($ESX in $ESXHosts) {
    Add-DnsServerResourceRecordA -ZoneName "domain.local" -Name $ESX.ESXiHostName -IPv4Address $ESX.ESXiHostIP #Add to DNS
    Start-Sleep -Seconds 5
    Add-vmhost -Name $ESX.ESXiHostName -location $Datacenter -credential $ESXCred -force -runasync -confirm:$false #Add to Datacenter
    Start-Sleep -Seconds 15 #wait...
    Get-Datastore -VMHost $ESX.ESXiHostName | Where-Object {$_.name -like "*datastore*"} | Set-Datastore -Name $ESX.Datastore #Rename Local Datastore
    Set-VMHost -VMHost $ESX.ESXiHostName -LicenseKey $vSphereKey #License the ESX
}

Start-Sleep -Seconds 15 #wait...

# SSH & NTP Configuration for all Hosts in the Datacenter

Get-VMHost | Where-Object {$_.name -ne "ESXi-01.domain.local"} | Add-VMHostNtpServer "dc-01.domain.local","dc-02.domain.local"
Get-VMHost | Where-Object {$_.name -ne "ESXi-01.domain.local"} | Get-VMHostFirewallException | Where-Object {$_.Name -eq "NTP client"} | Set-VMHostFirewallException -Enabled:$true
Get-VMHost | Where-Object {$_.name -ne "ESXi-01.domain.local"} | Get-VMHostService | Where-Object {$_.Key -eq "ntpd"} | Start-VMHostService
Get-VMHost | Where-Object {$_.name -ne "ESXi-01.domain.local"} | Get-VMHostService | Where-Object {$_.Key -eq "ntpd"} | Set-VMHostService -Policy On
Get-VMHost | Get-VMHostFirewallException | Where-Object {$_.Name -eq "SSH Server"} | Set-VMHostFirewallException -Enabled:$true
Get-VMHost | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"} | Start-VMHostService
Get-VMHost | Get-VMHostService | Where-Object {$_.Key -eq "TSM-SSH"} | Set-VMHostService -Policy On

# Join ESXi Server to the Domain
$ADCred = Get-Credential -Message "Please enter the password for the Domain Admin account for domain.LOCAL Domain" -UserName "administrator@domain.local"
Get-VMHost | Get-VMHostAuthentication | Set-VMHostAuthentication -JoinDomain -Domain "domain.local" -Credential $ADCred -Confirm:$false

Start-Sleep -Seconds 15 #wait...

# Create the Virtual Machines

Foreach ($VM in $VMs) {
    $hostname = $VM.hostname
    $MACAddress = $VM.macaddress
    $VMHost = $VM.VMHost
    $Datastore = $VM.Datastore
    $Path = $VM.Path
    Import-vapp -source $Path -VMHost $VMHost -Name:$hostname -Datastore $Datastore -DiskStorageFormat Thin
    $MyNetworkAdapter = Get-VM -Name $hostname | Get-NetworkAdapter -Name "Network Adapter 1"
    Set-NetworkAdapter -NetworkAdapter $MyNetworkAdapter -MacAddress $MACAddress -confirm:$false
}
<#
  .SYNOPSIS
    Configure vCenter with basic settings

  .DESCRIPTION
    Performs initial configuration for a vCenter - creates a datacenter and license the vCenter

  .PARAMETER Datacenter
      Enter the Location the ESXi should reside in - Cluster, Datacenter, etc.

  .PARAMETER vCenterKey
      The license key for the vCenter

  .INPUTS
    Parametrs as stated above

  .OUTPUTS
    None.

  .NOTES
    Version:        1.0
    Author:         Omer Barel
    Creation Date:  February 15, 2017
    Purpose/Change: Initial development

  .EXAMPLE
    Configure_vCenter.ps1 -Datacenter DC -vCenterKey XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
  #>

#----------------------------------------------------------[Parameters]----------------------------------------------------------

[CmdletBinding()]
Param(
   [Parameter(Mandatory=$True,HelpMessage="Enter the Name of the Datacenter as you'd like")]
   [string]$Datacenter,

   [Parameter(Mandatory=$True,HelpMessage="Enter the license key for the vCenter")]
   [string]$vCenterKey
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

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Host -ForegroundColor Black -BackgroundColor Yellow "Loading VMware automation modules. Please wait..."

Add-WindowsFeature -Name RSAT -IncludeAllSubFeature
Import-PowerCLI

# Connect to the vCenter

Connect-VIServer "vcenter.domain.local"

# Create New Datacenter
$Location = get-folder -norecursion
New-Datacenter -Location $Location -Name $Datacenter

# License the vCenter

$MyVC = Connect-VIServer "vcenter.domain.local"
$LicenseManager = Get-View ($MyVC.ExtensionData.Content.LicenseManager)
$LicenseManager.AddLicense($vCenterKey,$Null)
$LicenseAssignmentManager = Get-View ($LicenseManager.LicenseAssignmentManager)
$LicenseAssignmentManager.UpdateAssignedLicense($MyVC.InstanceUuid,$vCenterKey,$Null)
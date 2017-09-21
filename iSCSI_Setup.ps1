<#
.SYNOPSIS
  Configure iSCSI on a Windows Server

.DESCRIPTION
  The script will configure the iSCSI service on a Windows server against a NetApp storage with dual path

.INPUTS
  "\\storage\iscsiparams.csv

.OUTPUTS
  None

.NOTES
  Version:        1.0
  Author:         Omer Barel
  Creation Date:  February 7, 2017
  Purpose/Change: Initial script development
  
#>


#----------------------------------------------------------[Declarations]----------------------------------------------------------

$params=Import-Csv -Path "C:\DB\iscsiparams.csv"

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force
Set-Service -Name msiscsi -StartupType Automatic
Start-Service msiscsi
New-IscsiTargetPortal -TargetPortalAddress $params.ISCSILIF1
Connect-IscsiTarget -NodeAddress $params.NETAPPIQN -TargetPortalAddress $params.ISCSILIF1 -IsPersistent $true -IsMultipathEnabled $true -InitiatorPortalAddress $params.DBIP
Connect-IscsiTarget -NodeAddress $params.NETAPPIQN -TargetPortalAddress $params.ISCSILIF2 -IsPersistent $true -IsMultipathEnabled $true -InitiatorPortalAddress $params.DBIP
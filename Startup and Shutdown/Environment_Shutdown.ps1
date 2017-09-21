<#
    .SYNOPSIS
        Shutdown environment

    .DESCRIPTION
        This script will shutdown a declared environment
        Assumptions:
            * Physical servers are HP based
            * Servers are running either Windows 2012 R2 or vSphere ESXi 6.0 OS
            * Clients are running Windows 7
            * NetApp CDOT 8.x machine exists as the storage
        
        Prerequisites:
            * VMware PowerCli must be installed
            * PLINK.EXE should be in C:\Scripts\Putty
            * You must login to the NetApp Cluster & Nodes with Putty at least once before running the script to cache the NetApp certificate

    .PARAMETER LogFile
        Location to place the log file in. Defaults to "C:\Scripts\Environment_Shutdown.log" unless changed during execution

    .PARAMETER CsvData
        Location to read the .CSV file from. Defaults to "C:\Scripts\Computers.csv" unless changed during execution
        Example CsvData:
            hostname,type,ip,iLOIP,StartupPriority,ShutdownPriority
            esxi-01.domain.local,HPSrvESXi,10.195.7.11,10.195.7.71,1,26
            dc-01.domain.local,VMwareVM,10.195.7.6,,2,24
            wds.domain.local,VMwareVM,10.195.7.9,,3,23
            vcenter.domain.local,VMwareVM,10.195.7.10,,4,22

        CsvData is a combined file for both the startup & shutdown script and must be accurate according to your environment
        File should include all servers to shutdown with the desired priority for each
        Server with Priority 1 will turn off first, before server with Priority 2, and so on
            
    .INPUTS
        CsvData - contains all data for the machines that needs to shutdown.
                    
    .OUTPUTS
        Outputs will be written to the logfile in $logFile
        
    .NOTES
        Version:        1
        Author:         Omer Barel
        Creation Date:  July 6, 2017
        Purpose/Change: Production Version
        To Do:          Add Error Handling:
                            - Input validation
                            - Action to take if machine isn't reachable
                            - PLINK.EXE location validation
                            - Convert PLINK.EXE Location to parameter
                            - Modify NetApp portion to use NetApp PowerShell module
    
    .EXAMPLE
        
        Environment_Shutdown.ps1
        
        Running the script with default parameters for the desired log file location and the .CSV containing the computers (see PARANETERS section above)
        If you need to change default parameters please refer to the example below

    .EXAMPLE
        
        Environment_Shutdown.ps1 -LogFile "C:\MyScripts\Shutdown.log" -CsvData "C:\MyScripts\Computers.csv"

        Running the script with user supplied parameters for the desired log file location and the .CSV containing the computers
#>

#-----------------------------------------------------------[Functions & Declarations]------------------------------------------------------------

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $False, HelpMessage = "Enter the path to save the log file in")]
    [string]$LogFile = "C:\Scripts\Environment_Shutdown.log",
    [Parameter(Mandatory = $False, HelpMessage = "Enter the path to the .CSV with computers data")]
    [string]$CsvData = "C:\Scripts\Computers.csv"
)

Function Write-Log {
    <#
        .Synopsis
            Write-Log writes a message to a specified log file with the current time stamp.
        .DESCRIPTION
            The Write-Log function is designed to add logging capability to other scripts.
            In addition to writing output and/or verbose you can write to a log file for
            later debugging.
        .NOTES
            Created by: Jason Wasser @wasserja
            Modified: 11/24/2015 09:30:19 AM  

            Changelog:
                * Code simplification and clarification - thanks to @juneb_get_help
                * Added documentation.
                * Renamed LogPath parameter to Path to keep it standard - thanks to @JeffHicks
                * Revised the Force switch to work as it should - thanks to @JeffHicks

            To Do:
                * Add error handling if trying to create a log file in a inaccessible location.
                * Add ability to write $Message to $Verbose or $Error pipelines to eliminate
                duplicates.
        .PARAMETER Message
            Message is the content that you wish to add to the log file. 
        .PARAMETER Path
            The path to the log file to which you would like to write. By default the function will 
            create the path and file if it does not exist. 
        .PARAMETER Level
            Specify the criticality of the log information being written to the log (i.e. Error, Warning, Informational)
        .PARAMETER NoClobber
            Use NoClobber if you do not wish to overwrite an existing file.
        .EXAMPLE
            Write-Log -Message 'Log message' 
            Writes the message to c:\Logs\PowerShellLog.log.
        .EXAMPLE
            Write-Log -Message 'Restarting Server.' -Path c:\Logs\Scriptoutput.log
            Writes the content to the specified log file and creates the path and file specified. 
        .EXAMPLE
            Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error
            Writes the message to the specified log file as an error message, and writes the message to the error pipeline.
        .LINK
            https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = 'C:\Logs\PowerShellLog.log',
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber
    )

    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        
        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        else {
            # Nothing to see here yet.
        }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

Function Stop-Machine {
    <#
        .SYNOPSIS
            Stops a machine

        .DESCRIPTION
            The function takes Machine Type, IP & Name as parameters and shuts down the machine
            
        .PARAMETER Name
            The hostname of the machine

        .PARAMETER IP
            The IP of the machine

        .PARAMETER Type
            The type of the machine. Acceptable values: HPSrv, VMwareVM, HPClient, Storage

        .NOTES
            Version:        1
            Author:         Omer Barel
            Creation Date:  July 4, 2017
            Purpose/Change: Initial Development
        
        .EXAMPLE
            Stop-Machine -Type HPSrv -Name Server-01 -IP 100.0.0.101
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, HelpMessage = "Name of the Machine")]
        [string]$Name,        
        [Parameter(Mandatory = $True, HelpMessage = "IP of the Machine")]
        [string]$IP,
        [Parameter(Mandatory = $True, HelpMessage = "Type of the Machine")]
        [string]$Type
    )

    Function Stop-Windows {
            <#
                .SYNOPSIS
                    Stops a windows machine

                .DESCRIPTION
                    The function takes Machine Name as parameter and shuts down the machine
            
                .PARAMETER Name
                    The hostname of the machine

                .NOTES
                    Version:        1
                    Author:         Omer Barel
                    Creation Date:  July 4, 2017
                    Purpose/Change: Initial Development
        
                .EXAMPLE
                    Stop-Windows -Name Server-01 -IP 100.0.0.101
            #>
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory = $True, HelpMessage = "Hostname of the windows machine")]
                [string]$Name
            )
            
            if ((Test-Connection -BufferSize 32 -Count 1 -ComputerName $Name -Quiet) -eq $true) {
                Stop-Computer -ComputerName $Name -Credential $DomainAdminCredentials -Confirm:$false -Force
                Write-Log -Message "Shutting down $name " -Path $logfile -Level Info
            }
            else {
                Write-Log -Message "Can't reach $name, please manually check the status and shutdown the host" -Path $logfile -Level Warn
            }
    }

    Function Stop-ESX {
                <#
                .SYNOPSIS
                    Stops an ESXi host

                .DESCRIPTION
                    The function takes Machine Name as parameter and shuts down the machine
            
                .PARAMETER Name
                    The hostname of the machine

                .NOTES
                    Version:        1
                    Author:         Omer Barel
                    Creation Date:  July 4, 2017
                    Purpose/Change: Initial Development
        
                .EXAMPLE
                    Stop-ESX -Name Server-01
            #>
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory = $True, HelpMessage = "Hostname of the server")]
                [string]$Name
            )
            
            if ((Test-Connection -BufferSize 32 -Count 1 -ComputerName $Name -Quiet) -eq $True) {
                Connect-VIServer -Server $Name -Credential $ESXiCredentials
                Stop-VMHost -VMHost $Name -Server $Name -Confirm:$False -Force
                Write-Log -Message "Shutting down $Name " -Path $logfile -Level Info
            }
            else {
                Write-Log -Message "Can't reach $Name, please manually check the status and shutdown the host" -Path $LogFile -Level Warn
            }
    }

    If ($Type -eq "HPSrvESXi") {
        Stop-ESX -Name $Name
    }
    else {
        Stop-Windows -Name $Name
    }
}

Function Stop-NetApp {
    <#
        .SYNOPSIS
            Stops a NetApp Cluster

        .DESCRIPTION
                    
            Prerequisites:
                * PLINK.EXE should be in C:\Scripts\Putty
                * You must login to the NetApp Cluster & Nodes with Putty at least once before running the script to cache the NetApp certificate
            
        .PARAMETER NetAppCls
            Object containing the NetApp Logical cluster name & management IP

        .PARAMETER NetAppFiler1
            Object containing the 1st NetApp Node name & management IP

        .PARAMETER NetAppFiler2
            Object containing the 2nd NetApp Node name & management IP

        .PARAMETER NetAppPassword
            NetApp admin password                    

        .NOTES
            Version:        1
            Author:         Omer Barel
            Creation Date:  July 4, 2017
            Purpose/Change: Initial Development
        
        .EXAMPLE
            Stop-NetApp -NetAppCls $NetAppCls -NetAppFiler1 $NetAppFiler1 -NetAppFiler2 $NetAppFiler2 -NetAppPassword $NetAppPassword 
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, HelpMessage = "Management IP of the NetApp Cluster")]
        [string]$NetAppCls,
        [Parameter(Mandatory = $True, HelpMessage = "Management IP of the 1st NetApp Filer")]
        [string]$NetAppFiler1,
        [Parameter(Mandatory = $True, HelpMessage = "Management IP of the 2nd NetApp Filer")]
        [string]$NetAppFiler2,
        [Parameter(Mandatory = $True, HelpMessage = "NetApp Administrator Password")]
        [string]$NetAppPassword

    )

    Write-Log -Message "Shutting Down NetApp $NetAppCls, $NetAppFiler1, $NetAppFiler2, $NetAppPassword" -Path $logfile -Level Info
    Invoke-Command -ScriptBlock { & cmd.exe /c "C:\Scripts\Putty\PLINK.EXE" $NetAppCls.iLOIP -batch -l admin -pw $NetAppPassword cifs session close -node * }
    Invoke-Command -ScriptBlock { & cmd.exe /c "C:\Scripts\Putty\PLINK.EXE" $NetAppCls.iLOIP -batch -l admin -pw $NetAppPassword cluster ha modify -configured false }
    Invoke-Command -ScriptBlock { & cmd.exe /c "C:\Scripts\Putty\PLINK.EXE" $NetAppCls.iLOIP -batch -l admin -pw $NetAppPassword storage failover modify -node * -enabled false }
    Invoke-Command -ScriptBlock { & cmd.exe /c "C:\Scripts\Putty\PLINK.EXE" $NetAppFiler2.iLOIP -batch -l admin -pw $NetAppPassword halt local -inhibit-takeover true -ignore-quorum-warnings -skip-lif-migration-before-shutdown }
    Invoke-Command -ScriptBlock { & cmd.exe /c "C:\Scripts\Putty\PLINK.EXE" $NetAppFiler1.iLOIP -batch -l admin -pw $NetAppPassword halt local -inhibit-takeover true -ignore-quorum-warnings -skip-lif-migration-before-shutdown }    
}

## Read CSV file with machine names
$AllObjects = Import-Csv -Path $CsvData | Where-Object {$_.ShutdownPriority -ne ""}
$NetAppCls = Import-Csv -Path $CsvData | Where-Object {$_.hostname -eq "netapp"}
$NetAppFiler1 = Import-Csv -Path $CsvData | Where-Object {$_.hostname -eq "netapp1"}
$NetAppFiler2 = Import-Csv -Path $CsvData | Where-Object {$_.hostname -eq "netapp2"} 

# Gather credentials
$DomainAdminCredentials = Get-Credential -Message "Enter domain admin password" -UserName administrator@domain.local
$ESXiCredentials = Get-Credential -Message "Enter ESXi admin password" -UserName root
$NetAppPassword = Read-Host "Enter NetApp Password"

# Import Necessary Modules
Get-Module -ListAvailable | Where-Object {$_.Name -like "VMware*"} | Import-Module -Verbose

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message "=====================================================================================" -Path $logfile
Write-Log -Message "Beginning Shutdown Sequence for Environment..." -Path $logfile

for ($Counter = 1; $Counter -le $AllObjects.count; $Counter++) {
    
    $ArrayObject = $AllObjects | Where-Object {$_.ShutdownPriority -eq $Counter} 
    $Hostname = $ArrayObject.Hostname
    $IP = $ArrayObject.IP
    $Type = $ArrayObject.Type

    if ($Type -ne "storage") {
        Stop-Machine -Name $Hostname -IP $IP -Type $Type    
    }
    else {
        Stop-NetApp -NetAppCls $NetAppCls -NetAppFiler1 $NetAppFiler1 -NetAppFiler2 $NetAppFiler2 -NetAppPassword $NetAppPassword
    }
}

Write-Log -Message "Finished Shutdown Sequence for Environment. Please manually power down the NetApp shelves & Filers and Cisco Switches" -Path $logfile
Write-Log -Message "Please manually shutdown PDU L1-L6 in both Racks" -Path $logfile
Write-Log -Message "If any errors reported during the execution you should manually shutdown the unreachable host" -Path $logfile
Write-Log -Message "=====================================================================================" -Path $logfile
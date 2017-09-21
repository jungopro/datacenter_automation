<#
    .SYNOPSIS
        Boot the Environment

    .DESCRIPTION
        This script will boot a declared environment
        Assumptions:
            * Physical servers are HP based
            * Servers are running either Windows 2012 R2 or vSphere ESXi 6.0 OS
            * Clients are running Windows 7
            * Before running this script the switches and storage appliances should already be on and operational
        
        Prerequisites:
            * HP Powershell iLO Cmdlets must be installed
            * VMware PowerCli Cmdlets must be installed 
            * The first ESXi must have the following VMs on it: DC-01, WDS, vCenter

    .PARAMETER LogFile
        Location to place the log file in. Defaults to "C:\Scripts\Environment_Startup.log" unless changed during execution

    .PARAMETER CsvData
        Location to read the .CSV file from. Defaults to "C:\Scripts\Computers.csv" unless changed during execution
        Example CsvData:
            hostname,type,ip,iLOIP,StartupPriority,ShutdownPriority
            esxi-01.domain.local,HPSrvESXi,10.195.7.11,10.195.7.71,1,26
            dc-01.domain.local,VMwareVM,10.195.7.6,,2,24
            wds.domain.local,VMwareVM,10.195.7.9,,3,23
            vcenter.domain.local,VMwareVM,10.195.7.10,,4,22

        CsvData is a combined file for both the startup & shutdown script and must be accurate according to your environment
        File should include all servers to boot with the desired priority for each
        Server with Priority 1 will turn on first, before server with Priority 2, and so on

    .PARAMETER vCenter
        FQDN of the vCenter

    .PARAMETER ESXi01
        IP of the first ESXi Server holding the VMs DC-01, WDS and vCenter
            
    .INPUTS
        CsvData - contains all data for the machines that needs to startup.
                    
    .OUTPUTS
        Outputs will be written to the logfile in $logFile

    .EXAMPLE
        
        Environment_Startup.ps1
        
        Running the script with default parameters for the desired log file location and the .CSV containing the computers (see PARANETERS section above)
        If you need to change default parameters please refer to the example below

    .EXAMPLE
        
        Environment_Startup.ps1 -LogFile "C:\MyScripts\Startup.log" -CsvData "C:\MyScripts\Computers.csv"

        Running the script with user supplied parameters for the desired vCenter server, log file location and the .CSV containing the computers

    .NOTES
#>

#-----------------------------------------------------------[Functions & Declarations]------------------------------------------------------------

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $False, HelpMessage = "Enter the FQDN of the vCenter Server")]
    [string]$vCenter = "vcenter.domain.local",
    [Parameter(Mandatory = $False, HelpMessage = "Enter the FQDN of the first ESXi Server, holding DC-01, WDS and vCenter")]
    [string]$ESXi01 = "10.195.7.11",
    [Parameter(Mandatory = $False, HelpMessage = "Enter the full path to the LogFile")]
    [string]$LogFile = "C:\Scripts\Startup.log",
    [Parameter(Mandatory = $False, HelpMessage = "Enter the full path to the .CSV file with all computers data")]
    [string]$CsvData = "C:\Scripts\Computers.csv"
)

Function Write-Log {
    <#
        .Synopsis
            Write-Log writes a message to a specified log file with the current time stamp.

        .DESCRIPTION
            The Write-Log function is designed to add logging capability to other scripts.
            In addition to writing output and/or verbose you can write to a log file for later debugging.

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
                * Add ability to write $Message to $Verbose or $Error pipelines to eliminate duplicates.

        .PARAMETER Message
            Message is the content that you wish to add to the log file. 

        .PARAMETER Path
            The path to the log file to which you would like to write. By default the function will create the path and file if it does not exist. 

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

Function Test-Boot {
    <#
        .SYNOPSIS
            Check machine boot status

        .DESCRIPTION
            The function takes IP & Names as parameters and check boot of a machine with the usage of the echo command
    
        .NOTES
            Version:        1
            Author:         Omer Barel
            Creation Date:  Feburary 26, 2017
            Purpose/Change: Initial Development
    
        .EXAMPLE
            Test-Boot -IP 192.168.120.47 -name dc-01.domain.local
    #>	

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, HelpMessage = "IP of the server")]
        [string]$IP,
        [Parameter(Mandatory = $True, HelpMessage = "Name of the server")]
        [string]$Name
    )
    $TimeOut = 600
    $Replies = 60
    $j = 1
    $Ping = New-Object System.Net.NetworkInformation.Ping
    do {
        $Echo = $Ping.Send($IP)
        Write-Progress -ID 1 -Activity "Waiting for $name to respond to echo" -PercentComplete ($j * 100 / $TimeOut)
        Start-Sleep 1
        if ($j -eq $TimeOut) {
            Write-Log -Message "Time out expired, aborting." -Path $LogFile -Level Error
            Return $False
            exit
        }
        $j++
    }
    while ($Echo.Status.ToString() -ne "Success" )

    ## Machine is alive, keep sending for $Replies amount
    for ($k = 1; $k -le $Replies; $k++) { 
        Write-Progress -ID 1 -Activity "Waiting for $name to respond to echo" -PercentComplete (100) 
        Write-Progress -Id 2 -ParentId 1 -Activity "Receiving echo reply"  -PercentComplete ($k * 100 / $Replies)
        Start-Sleep 1
    }
    $i++
    Write-Progress -Id 2 -Completed $true
    Write-Log -Message "$name is up" -Path $LogFile -Level Info
    Return $True
}

Function Start-Machine {
    <#
        .SYNOPSIS
            Starts a machine

        .DESCRIPTION
            The function takes Machine Type, IP & Name as mandatory parameters and iLOIP as optional parameter and boots a server in a powered-off state
            It will then check the boot status of a machine with the usage of the echo command

        .PARAMETER Name
            The hostname of the machine

        .PARAMETER IP
            The IP of the machine

        .PARAMETER Type
            The type of the machine. Acceptable values: HPSrv, VMwareVM, HPClient

        .PARAMETER iLOIP
            The iLO IP of the machine. Optional value, applicable for physical servers
    
        .NOTES
            Version:        1
            Author:         Omer Barel
            Creation Date:  July 4, 2017
            Purpose/Change: Initial Development
        
        .EXAMPLE
            Start-Machine -Type HPSrv -Name Server-01 -IP 100.0.0.101 -iLOIP 100.0.99.101
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, HelpMessage = "Name of the Machine")]
        [string]$Name,
        [Parameter(Mandatory = $False, HelpMessage = "iLOIP of the Machine")]
        [string]$iLOIP,
        [Parameter(Mandatory = $True, HelpMessage = "IP of the Machine")]
        [string]$IP,
        [Parameter(Mandatory = $True, HelpMessage = "Type of the Machine")]
        [string]$Type
    )

    Function Start-HPSrv {
        <#
            .SYNOPSIS
                Starts a server

            .DESCRIPTION
                The function takes iLOIP, IP & Name as parameters and boots a server in a powered-off state
                It will then check the boot status of a machine with the usage of the echo command
        
            .NOTES
                Version:        1
                Author:         Omer Barel
                Creation Date:  March 28, 2017
                Purpose/Change: Initial Development
            
            .EXAMPLE
                Start-HPSrv -Name Server-01 -IP 100.0.0.101 -iLOIP 100.0.99.101
        #>

        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $True, HelpMessage = "Name of the server")]
            [string]$Name,
            [Parameter(Mandatory = $True, HelpMessage = "iLOIP of the server")]
            [string]$iLOIP,
            [Parameter(Mandatory = $True, HelpMessage = "IP of the server")]
            [string]$IP
        )

        Write-Log -Message "Turning on $Name" -Path $LogFile -Level Info
        Set-HPiLOHostPower -Server $iLOIP -Credential $iLOCred -HostPower On -DisableCertificateAuthentication
    }

    Function Start-VMwareVM {
        <#
            .SYNOPSIS
                Starts a VMware VM

            .DESCRIPTION
                The function takes VM Name as a parameter and boots a VM in a powered-off state
                It will then check the boot status of a machine with the usage of the echo command
        
            .NOTES
                Version:        1
                Author:         Omer Barel
                Creation Date:  March 28, 2017
                Purpose/Change: Initial Development
            
            .EXAMPLE
                Start-VMwareVM -Name VM01
        #>

        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $True, HelpMessage = "Name of the VM")]
            [string]$Name,
            [Parameter(Mandatory = $True, HelpMessage = "IP of the VM")]
            [string]$IP
        )

        $NameArray = $Name.Split(".")
        $VMName = $NameArray[0]
        Write-Log -Message "Turning on $VMName" -Path $LogFile -Level Info
        Connect-VIServer -Server $vCenter -Credential $vCenterCred
        Start-VM -VM $VMName -ErrorAction SilentlyContinue
        Disconnect-VIServer -Server $vCenter -Confirm:$false
    }

    If ($Type -eq "HPSrvWin" -or $Type -eq "HPSrvESXi") {
        Start-HPSrv -Name $Name -iLOIP $iLOIP -IP $IP
        Test-Boot -IP $IP -Name $Name
    }
    elseif ($Type -eq "VMwareVM") {
        Start-VMwareVM -Name $Name -IP $IP
        Test-Boot -IP $IP -Name $Name
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

## Read CSV file with machine names
$AllObjects = Import-Csv -Path $CsvData | Where-Object {$_.StartupPriority -ne ""}

# Gather credentials
$iLOCred = Get-Credential -Message "Enter iLO Admin Credentials" -UserName iadmin
$vCenterCred = Get-Credential -Message "Enter vCenter Admin Credentials" -UserName domain\Administrator
$ESXi01Cred = Get-Credential -Message "Enter ESXi01 root Credentials" -UserName root

# Import Necessary Modules
Import-Module HPiLOCmdlets -Verbose
Get-Module -ListAvailable | Where-Object {$_.Name -like "VMware*"} | Import-Module -Verbose

Write-Log -Message "=====================================================================================" -Path $LogFile
Write-Log -Message "Beginning Startup Sequence for Environment..." -Path $LogFile -Level Info
    
for ($Counter = 1; $Counter -le $AllObjects.Count; $Counter++) {

    $ArrayObject = $AllObjects | Where-Object {$_.StartupPriority -eq $Counter} 
    $Hostname = $ArrayObject.Hostname
    $iLOIP = $ArrayObject.iLOIP
    $IP = $ArrayObject.IP
    $Type = $ArrayObject.Type    
    if ($Type -ne "storage" -and $Type -ne "HPClient") {
        if ($ArrayObject.StartupPriority -eq 4 -or $ArrayObject.StartupPriority -eq 3 -or $ArrayObject.StartupPriority -eq 2) {
            $NameArray = $HostName.Split(".")
            $VMName = $NameArray[0]                     
            try {
                Connect-VIServer -Server $ESXi01 -Credential $ESXi01Cred
                Write-Log -Message "Turning on $VMName" -Path $LogFile -Level Info
                Start-VM -VM $VMName -ErrorAction Stop
                Test-Boot -IP $IP -Name $Hostname
            }
            catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidPowerState] {
                Write-Log -Message "$VMName is on. Proceeding to next step" -Path $LogFile -Level Info
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Write-Log -Message "Error! The error is: $ErrorMessage `nAborting program. Please fix the error and re-run the program" -Path $LogFile -Level Error
                Exit
            }
            finally {
                Disconnect-VIServer -Server $ESXi01 -Confirm:$false
            }
        }
        else {
            Write-Log -Message "Starting $Hostname" -Path $LogFile -Level Info
            Start-Machine -Name $Hostname -iLOIP $iLOIP -IP $IP -Type $Type
        }   
    }
}

Write-Log -Message "Finished Startup Sequence for the Environment" -Path $LogFile -Level Info
Write-Log -Message "=====================================================================================" -Path $LogFile
Write-Host 'This Script Will add a pre-staged device to WDS and DHCP'

$devices = Import-Csv "\\storage\WDS_DHCP_Data.csv"

foreach ($device in $devices){
    $hostname=$device.Name
    $MacAddress=$device.MAC
    $BootImagePath=$device.BootImagePath
    $WdsClientUnattend=$device.WdsClientUnattend
    $user=$device.user
    $JoinRights=$device.JoinRights
    $ReferralServer=$device.ReferralServer
    $OU=$Device.OU
    $IP=$Device.IP
    Wdsutil /add-device /Device:$Hostname /ID:$MacAddress /BootImagePath:$BootImagePath /WDSClientUnattend:$WdsClientUnattend /User:$user /JoinRights:$JoinRights /ReferralServer:$ReferralServer
    Get-ADComputer -filter 'Name -eq $hostname' | Move-ADObject -TargetPath $OU
    Add-DhcpServerv4Reservation -ScopeId 192.168.1.0 -IPAddress $IP -ClientId $MacAddress -Description $hostname -Name $hostname
}
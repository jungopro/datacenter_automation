Write-Host 'This Script Will add a pre-staged device to DHCP'

$Servers = Import-Csv "\\storage\DHCP_Data_ESXi.csv"

foreach ($device in $Servers){
    $hostname=$device.Name
    $MacAddress=$device.MAC
    $IP=$Device.IP
    Add-DhcpServerv4Reservation -ScopeId 192.168.1.0 -IPAddress $IP -ClientId $MacAddress -Description $hostname -Name $hostname
}

$Workstations = Import-Csv "\\storage\WDS_DHCP_Data-Workstations.csv"

foreach ($device in $Workstations){
    $hostname=$device.Name
    $MacAddress=$device.MAC
    $IP=$Device.IP
    Add-DhcpServerv4Reservation -ScopeId 192.168.1.0 -IPAddress $IP -ClientId $MacAddress -Description $hostname -Name $hostname
}

$Servers_MGMT = Import-Csv "\\storage\DHCP_Data_MGMT.csv"

foreach ($device in $Servers_MGMT){
    $hostname=$device.Name
    $MacAddress=$device.MAC
    $IP=$Device.IP
    Add-DhcpServerv4Reservation -ScopeId 192.168.2.0 -IPAddress $IP -ClientId $MacAddress -Description $hostname -Name $hostname
}
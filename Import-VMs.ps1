# Create the Virtual Machines

$VMs = import-csv -Path "C:\vCenter\Templates\VMs.csv"

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
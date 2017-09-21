# Datacenter Automation

Scripts to automate operations of an on-premise datacebter

## Environment description

**Please read the environmental description below before using the scripts**

- The environment is based on HP G9 servers that has the iLO module enabled and functional
- The server are running either Windows Server 2012 R2 or VMware vSphere ESXi 6.0 OS
- The environemnt includes a vCenter server controlling the ESXi servers
- The servers in the environment need to start and stop in a specific order

## Startup & Shutdown scripts

- Both scripts are using the Computers.csv as their input
- There are specific PS modules that needs to be installed on the client machine executing the scrip before actual execution
# About CreateVSwitch

An external virtual switch allows the management operating system to share an external network. The Hyper-V Virtual Switch Manager GUI interface allows a single share.

This script connects to multiple VLANs the management Windows OS of any workstation capable of running Hyper-V. Each virtual interface can be configured independently, much like a port on a physical switch.

The final network configuration is left to the user's creativity ;-)

The script relies on a configuration file enumerating the desired VLANs in the following format:

<VLAN_ID>	<VLAN_Description>	[(<Subnet>/<SubnetWidth>;<GatewayIP>)[,(<Subnet>/<SubnetWidth>;<GatewayIP>)[....]]]

where
- <VLAN_ID> is the VLAN identifier to assign to a "port" of the virtual switch
- <VLAN_Description> is a name that will be assigned to this "port"
- [...] is an **optional** list of network routes that will be accessible from this "port".
Each tuple is enclosed in () and is composed of a subnet specification and a gateway IP that will be accessible from this port. These are delimited by a ; within the tuple and a comma separated list of tuples can be specified. Although both IPv4 and IPv6 subnets and addresses can be specified, the parsing here is minimal and some errors will only get caught at runtime.

No white space is allowed in any of the parameters. Comments can be inserted using the usual # caracter.

Example configuration file:

```
# VLAN 201 reserved for support staff
201	Support	(10.30.0.0/16;10.200.200.241),(192.168.0.0/16;10.200.200.241)
# Projects
400	Project_400
401	Project_401
# Default untagged entry
0	Untagged
```

In the above example, the gateway 10.200.200.241 must be accessible using the effective routing table when the NIC configured for VLAN 201 is enabled. When this NIC is disabled, the two subnets in the example are not reachable.

------
>**Caution:**	This script requires **elevated** execution privileges.

Quoting from Microsoft's "about_Execution_Policies" : "PowerShell's
execution policy is a safety feature that controls the conditions
under which PowerShell loads configuration files and runs scripts."

Use any configuration that is the equivalent of the
following commnand executed from an elevated PowerShell prompt:

			Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Unrestricted
------

## Operation:

You must run PowerShell as an administrator. Invoke the script (relative path not specified here).
Script parameters are:

	ConfigueVSwitch.ps1 -DefaultManagementSwitch=<string> -DefaultPhysicalPortName=<string>

where:

- -DefaultManagementSwitch:     is the virtual switch name as will be displayed in Hyper-V. There default value is "ManagementSwitch".

- -DefaultPhysicalPortName:     is the name that will be assigned to the external NIC. There default value is "$Switch".
								When the script deletes the management switch (see below), the adapter is renamed "Ethernet XX-YY-ZZ" where XX-YY-ZZ are the last 6 digits of the MAC address.

The script can be invoked with a righ-click "Execute with PowerShell" and will attempt privilege escalation if possible.

On entry, the user must select the configuration file that will be used. If no file is selected, the script defaults to a simple untagged configuration.

The script displays a grid-view of the available VLANs and the user MUST select the desired VLANs in this instance. If the user aborts at this point, the virtual management switch is deleted.

The script disables ALL the VLANs that it configures. It will launch the Network Connections Control Panel where you can configure and enable each virtual adapter to your liking.

**Caution:** Enabling multiple adapters with a default route can result in loss of connectivity to your system. Please review the adapter metric for desired default route: it is typically 25 for a Gigabit adapter and the value 10 is suggested if more than one adapter was assigned a default route (using a DHCP server, for example).

**Caution:** You can remotely configure a system if you maintain untagged (access) on your trunk. As stated above, all VLANs configured by this script are disabled on exit and you must have an alternte way to reach the system if you want to avoid loss of connectivity.

## Sample console output based on the example configuration

```
  
Create multiple VLANs for Windows 10/11
---------------------------------------

        (This script is based on an idea from Alexander Taeffner
		see https://taeffner.net/2022/04/multiple-vlans-windows-10-11-onboard-tools-hyper

PowerShell version:  . 5.1.22621.2506

Status of Hyper-V services on this system:                                                                              
------------------------------------------

DisplayName                                                    FeatureName                               State          
-----------                                                    -----------                               -----          
Hyper-V                                                        Microsoft-Hyper-V-All                   Enabled          
Plateforme Hyper-V                                             Microsoft-Hyper-V                       Enabled          
Outils d’administration Hyper-V                                Microsoft-Hyper-V-Tools-All             Enabled          
Module Hyper-V pour Windows PowerShell                         Microsoft-Hyper-V-Management-PowerShell Enabled          
Hyperviseur Hyper-V                                            Microsoft-Hyper-V-Hypervisor            Enabled          
Services Hyper-V                                               Microsoft-Hyper-V-Services              Enabled          
Outils de gestion de l’interface graphique utilisateur Hyper-V Microsoft-Hyper-V-Management-Clients    Enabled

WARNING : Note: This script will not attempt ANY recovery in case of errors.

Configuration selected:
-----------------------

 ID Name        Routes
 -- ----        ------
201 Support     (10.30.0.0/16;10.200.200.241),(192.168.0.0/16;10.200.200.241)
400 Project_400
401 Project_401
  0 Untagged



VLANs for virtual switch : ManagementSwitch (Physical adapter: Ethernet 3C-08-7A )
----------------------------------------------------------------------------------
Adding:  201 Support
Adding:  400 Project_400
Adding:  401 Project_401
WARNING : Waiting 5 seconds for the system to identify the new interfaces...

MACAddress        VLANId     Mode PortName
----------        ------     ---- --------
00-15-5D-12-1F-62    401   Access Project_401
00-15-5D-12-1F-60    201   Access Support
48-21-0B-3C-08-7A      0 Untagged Untagged
00-15-5D-12-1F-61    400   Access Project_400


VLAN  401 Port Project_401 is now disabled.
VLAN  201 Port Support is now disabled.
VLAN  400 Port Project_400 is now disabled.

The network adapter has been renamed $Switch.

Routes with a limited lifetime value:
-------------------------------------

ifIndex DestinationPrefix NextHop      InterfaceAlias   ValidLifetime
------- ----------------- -------      --------------   -------------
     22 0.0.0.0/0         192.168.18.1 $Switch Untagged 12:00:00


Please review the adapter metric for desired default route. It is typically 25 for a Gigabit adapter
and the value 10 is suggested if more than one adapter was assigned a default route.

Current default route(s):


InterfaceAlias  : $Switch Untagged
InterfaceMetric : 25


Press Enter to continue...:

```

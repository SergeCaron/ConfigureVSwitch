##******************************************************************
## Revision date: 2024.03.12
##
##		2023.11.10: Proof of concept / Initial release
##		2024.02.25: Get VLAN list from configuration file
##		2024.03.06: Formatting
##
## Copyright (c) 2023-2024 PC-Évolution enr.
## This code is licensed under the GNU General Public License (GPL).
##
## THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
## ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
## IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
## PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
##
##******************************************************************
param (
	# Default Virtual Switch name
	[parameter()]
	[string]$DefaultManagementSwitch = 'ManagementSwitch',
	# Default Adapter Name of the Virtual Switch
	[parameter()]
	[string]$DefaultPhysicalPortName = '$Switch'
)

# PowerShell version number
$RunTimeVersion = $PSVersionTable.PSVersion -join "."

#$DefaultManagementSwitch = 'ManagementSwitch'
#$DefaultPhysicalPortName = '$Switch'


# Privilege Elevation Source Code: https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell

# Get the ID and security principal of the current user account
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)

# Get the security principal for the administrator role
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

# Check to see if we are currently running as an administrator
if ($myWindowsPrincipal.IsInRole($adminRole)) {
	# We are running as an administrator
	Clear-Host
	Write-Host "Create multiple VLANs for Windows 10/11"
	Write-Host "---------------------------------------"
	Write-Host
	Write-Host "	(This script is based on an idea from Alexander Täffner"
	Write-Host "	see https://taeffner.net/2022/04/multiple-vlans-windows-10-11-onboard-tools-hyper-v/)"
	Write-Host
	Write-Host "PowerShell version: ". $RunTimeVersion
	Write-Host
}
else {
	# We are not running as an administrator, so relaunch as administrator

	# Create a new process object that starts PowerShell
	$newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"

	# Specify the current script path and name as a parameter with added scope and support for scripts with spaces in it's path
	$newProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"

	# Indicate that the process should be elevated
	$newProcess.Verb = "runas"

	# Start the new process
	[System.Diagnostics.Process]::Start($newProcess)

	# Exit from the current, unelevated, process
	Exit
}

# Run your code that needs to be elevated here...

# Check that minimal Hyper-V management features are installed

Write-Host "Status of Hyper-V services on this system:"
Write-Host "------------------------------------------"
$HyperVState = Get-WindowsOptionalFeature -Online -FeatureName *hyper-v* | Select-Object DisplayName, FeatureName, State
$HyperVState | Format-Table * -AutoSize

$HyperVEnabled = $True
ForEach ( $Feature in @( "Microsoft-Hyper-V-Management-PowerShell", "Microsoft-Hyper-V-Services") ) {
	# Note: "Microsoft-Hyper-V-Services" is not a component in Windows Server
	If ((Get-WindowsOptionalFeature -Online -FeatureName $Feature).State -eq "Disabled") {
		Write-Warning "Windows feature $Feature must be installed before using this script."
		$HyperVEnabled = $False
	}
}
If ($HyperVEnabled) {
	Write-Warning "Note: This script will not attempt ANY recovery in case of errors."
}
Else {
	Pause
	Exit 911
}

Write-Host

# Get the filename containing the VLAN list, if any.
Add-Type -AssemblyName System.Windows.Forms
$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
	# InitialDirectory = [Environment]::GetFolderPath('Desktop') 
	InitialDirectory = $script:MyInvocation.MyCommand.Path
	Filter           = ''
	Title            = 'Please locate your list of VLANs'
}
$Void = $FileBrowser.ShowDialog()

# Get the list of VLANs, which may be a null string if it contains only comments or if the user aborts:
If ( ![string]::IsNullOrEmpty($FileBrowser.FileName) ) {
	$RequiredVLANs = (Get-Content $FileBrowser.FileName) -match "^[^#]" | ConvertFrom-String -PropertyNames ID, Name, Routes
}
else {
	$RequiredVLANs = $Null
}
# Make sure we have an array!
If ( $Null -eq $RequiredVLANs ) {
	$RequiredVLANs = @()
}
elseif ($RequiredVLANs.GetType().Name -eq "PSCustomObject") {
	$RequiredVLANs = @( $RequiredVLANs )
}

# Add a default Untagged value
If (! ($RequiredVLANs.ID -contains 0) )	{
	$RequiredVLANs += @( [PSCustomObject] @{ ID = 0; Name = "Untagged"; Routes = "" } )
}

# Sanity check: we should only have VLAN ID, name, and optional routes
If ( ($RequiredVLANs | Get-Member -MemberType NoteProperty | Measure-Object).Count -ne 3) {
	# We inherited some other property: don't trust this cinfiguration file.
	Write-Warning $($FileBrowser.FileName + " is not properly formatted.")
	Pause
	Exit 911
}

# Let the user select its choice of VLANs
$RequiredVLANs = $RequiredVLANs | Out-GridView -PassThru -Title "Please select ALL VLANs that should be managed on the target network interface:"
Write-Host "Configuration selected:"
Write-Host "-----------------------"
$RequiredVLANs | Out-Host
	
# Parse the routes associated with these VLANs for VPN clients
$RequiredVLANs | Add-Member -Name "Routing" -MemberType NoteProperty -Value @()
# Property Routing is not displayed during the Grid-View selection
ForEach ($VLAN in $RequiredVLANs) {
	If ( ![string]::IsNullOrEmpty($VLAN.Routes) ) {
		$Routing = @()
		$Networks = $VLAN.Routes -split ","	# Enumeration style (ne.tw.or.k/bits;ip.ad.dr.ess);(ne.tw.or.k/bits;ip.ad.dr.ess)...
		$IgnoreNetworks = $False

		ForEach ($Network in $Networks) {
			Try {
				$Junk = $ErrorActionPreference # Tuck this away ;-)
				$ErrorActionPreference = "Stop"
				If ( $Network -match "^\((?<Prefix>[A-Za-z\d.:]+/\d+);(?<Gateway>[A-Za-z\d.:]+)\)$" ) {
					$Void = $($Matches.Prefix.Trim().Split("/"))
					If ([int] $Void[1] -le 64) {
						$Void = [IPAddress]$Void[0]
						$Void = [IPAddress]$Matches.Gateway.Trim()
						$Routing += [PSCustomObject] @{ Prefix = $Matches.Prefix; Gateway = $Matches.Gateway }
					}
					else {
						Throw
					}
				}
				else {
					Throw
				}
			}
			Catch {
				Write-Warning $( $VLAN.Routes + " ignored for VLan id " + $VLAN.ID + ".")
				$IgnoreNetworks = $True
			}
			Finally {
				$ErrorActionPreference = $Junk # Restore ...
			}
		}

		If ($IgnoreNetworks) {
			Write-Host ""	# Only if warnings were issued
		}
		else { 
			$VLAN.Routing = $Routing		# Only if all routes appear valid (which may or may not be true ...)
		}
	}
}

# Get all virtual switches
[System.Object] $AllPhysicalPorts = Get-NetAdapter | Get-NetAdapterBinding | Where-Object { ($_.Enabled -eq $true) -and ($_.ComponentID -eq "vms_pp") }
If ($AllPhysicalPorts.ComponentID.Count -gt 0) {
	$Caution = @"
There are currently one or more virtual switches defind in this Hyper-V Configuration.
It is recommended to remove this configuration before defning multiple VLANs for the management OS.
Such removal may cause lost of connectivity to the network. The default route(s) will be displayed
before and after removing any switch associated with a physical network adapter.

Note that this script may hang if you redefine the same virtual switch without first deleting it.
"@
	Write-Warning $Caution

	$AllPhysicalPorts | Format-Table @{Label = "Nom du port physique"; Expression = { $_.Name } }, InterfaceDescription, Description -AutoSize
	If ($(Read-Host "Enter 'Yes' to proceed, anything else to continue").tolower().StartsWith('yes')) {

		# Display the default route(s) BEFORE removing the virtual switche(s).
		# Unfortunately "Get-NetNeighbor -PolicyStore ActiveStore -State Reachable | ft ifIndex, IPAddress, LinkLayerAddress"
		# is unreliable. Get default routes
		$Foreground = $host.UI.RawUI.ForegroundColor
		$host.UI.RawUI.ForegroundColor = "Green"

		Write-Host
		Write-Host "Current default route(s)"
		Write-Host "------------------------"
		Try {
			$DefaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -PolicyStore ActiveStore -ErrorAction Stop
			$DefaultRoutes | Format-Table InterfaceAlias, InterfaceIndex, NextHop
		}
		Catch {
			$DefaultRoutes = $Null
			Write-Host "None!"
		}

		ForEach ($Gateway in $DefaultRoutes.NextHop) {
			If ( $(Test-NetConnection -ComputerName $Gateway -InformationLevel Quiet)) {
				Write-Host $Gateway, "is reachable."
			}
		}

		$host.UI.RawUI.ForegroundColor = $Foreground

		# Retirer tous les commutateurs virtuels associés
		ForEach ($PhysicalPort in $AllPhysicalPorts) {

			$Adapter = Get-NetAdapter -InterfaceDescription $PhysicalPort.InterfaceDescription
			$Adapter | Format-Table Name, PhysicalMediaType, LinkSpeed, MacAddress

			$Switch = Get-VMSwitch -SwitchType External | Where-Object { $_.NetAdapterInterfaceDescription -eq $PhysicalPort.InterfaceDescription }
			$Switch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription

			$DefinedVLANs = Get-VMNetworkAdapterVlan -ManagementOS | Where-Object { $_.ParentAdapter.SwitchName -eq $Switch.Name }

			ForEach ($Port in $DefinedVLANs) {
				$Junk = $( "Removal of VLAN " + $Port.AccessVlanId + " (" + $Port.ParentAdapter.Name + ")" )
				If ( ($Port.OperationMode -eq 'Access') -or ($Port.OperationMode -eq 'Untagged') ) {
					Remove-VMNetworkAdapter -ManagementOS -SwitchName $Switch.Name -Name $Port.ParentAdapter.Name
					Write-Warning $( "Removal of VLAN " + $Port.AccessVlanId + " (" + $Port.ParentAdapter.Name + ")" )
				}
			}

			Write-Warning $( "Removal of virtual switch " + $Switch.Name )
			Remove-VMSwitch -Name $Switch.Name -Force

			Rename-NetAdapter -InputObject $Adapter -NewName $( "Ethernet " + $Adapter.MacAddress.SubString(9) )
		}

		Write-Warning "Waiting 5 seconds for the system to identify the new interfaces..."
		Start-Sleep -Seconds 5

		$Foreground = $host.UI.RawUI.ForegroundColor
		$host.UI.RawUI.ForegroundColor = "Green"

		Write-Host
		Write-Host "New default route(s)"
		Write-Host "------------------------"
		# Display the default route(s) AFTER removing the virtual switche(s).
		# Unfortunately "Get-NetNeighbor -PolicyStore ActiveStore -State Reachable | ft ifIndex, IPAddress, LinkLayerAddress"
		# is unreliable. Get default routes
		Try {
			$DefaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -PolicyStore ActiveStore -ErrorAction Stop
			$DefaultRoutes | Format-Table InterfaceAlias, InterfaceIndex, NextHop
		}
		Catch { 
			$DefaultRoutes = $Null
			Write-Host "None!"
		}

		ForEach ($Gateway in $DefaultRoutes.NextHop) {
			If ( $(Test-NetConnection -ComputerName $Gateway -InformationLevel Quiet)) {
				Write-Host $Gateway, "is reachable."
			}
		}

		$host.UI.RawUI.ForegroundColor = $Foreground

	}
}

Write-Host

If ($Null -ne $RequiredVLANs) {

	# Get THE virtual switch (Only one switch is supported in this script).

	[System.Object] $Switch = Get-VMSwitch -SwitchType External
	If ($Switch.Count -eq 1) {
		$Adapter = Get-NetAdapter -InterfaceDescription $Switch.NetAdapterInterfaceDescription
	}
	ElseIf ($Switch.Count -eq 0) {
		# Only Ethernet media is supported.
		[System.Object] $Adapter = (Get-NetAdapter | Where-Object { $_.Status -eq "UP" -and $_.PhysicalMediaType -eq "802.3" })
		If ($Adapter.Name.Count -gt 1) {
			# The user should select only one of those
			$Adapter = $Adapter | Out-GridView -PassThru -Title "Please select the target network interface:"
		}
		If ($Adapter.Name.Count -eq 1) {
			[System.Object] $Switch = New-VMSwitch -Name "$DefaultManagementSwitch" -NetAdapterName $Adapter.Name # Implicit -SwitchType External
			# Note: this also creates a untagged port (VLAN 0, even if there is no such thing ;-)
		}
		Else {
			# The user did not select only one network adapter
			Write-Warning "This script supports the configuration of a single network adapter."
			Pause
			Exit 911
		}
	}
	Else {
		# There are more than one virtual switch!
		Write-Warning "This script supports a single virtual switch. You are welcomed to clean this configuration ;-)"
		Pause
		Exit 911
	}

	Write-Host "VLANs for virtual switch :", $Switch.Name, "(Physical adapter:", $Adapter.Name, ")"
	Write-Host "----------------------------------------------------------------------------------"

	# Get the status of the switch on this system
	$ManagedVLANs = @()
	ForEach ( $Port in $(Get-VMNetworkAdapterVlan -ManagementOS | Where-Object { $_.ParentAdapter.SwitchName -eq $Switch.Name }) ) {
		$ManagedVLANs += New-Object -Type PSOBJECT -Property @{
			Mode     = $Port.OperationMode
			VLANId   = $Port.AccessVlanId
			PortName = $Port.ParentAdapter.Name
		}
	}

	# Add missing VLANs:
	ForEach ($VLAN in $RequiredVLANs) {
		If (-not ($VLAN.ID -in $ManagedVLANs.VLANId)) {
			$ThisOne = Add-VMNetworkAdapter -ManagementOS -SwitchName $Switch.Name -Name $VLAN.Name -Passthru
			If ($VLAN.ID -eq 0) { 
				$ThisOne | Set-VMNetworkAdapterVlan -Untagged
			}
			Else {
				$ThisOne | Set-VMNetworkAdapterVlan -Access -VlanId $VLAN.ID
			}
			Write-Host "Adding: ", $VLAN.ID, $VLAN.Name
		}
		Else {
			$Port = Get-VMNetworkAdapterVlan -ManagementOS `
			| Where-Object { ($_.ParentAdapter.SwitchName -eq $Switch.Name ) -and `
				(($_.OperationMode -eq "Access" -and $_.AccessVlanId -eq $VLAN.ID) -or ($_.OperationMode -eq "Untagged" -and $VLAN.ID -eq 0)) }
				
			If ( $Port.ParentAdapter.Name -ne $VLAN.Name) {
				Rename-VMNetworkAdapter -ManagementOS -Name $Port.ParentAdapter.Name -NewName $VLAN.Name
			}
		}
	}

	# Remove what is no longer used: the Windows 10/11 GUI does not allow you to delete this type of interface
	ForEach ($VLAN in $ManagedVLANs) {
		If (($VLAN.Mode -eq "Access" -or $VLAN.Mode -eq "Untagged") -and -not ($VLAN.VLANId -in $RequiredVLANs.ID)) {
			Remove-VMNetworkAdapter -ManagementOS -SwitchName $Switch.Name -Name $VLAN.PortName
			Write-Host "Removing :", $VLAN.VLANId, $VLAN.PortName
		}
	}
	
	Write-Warning "Waiting 5 seconds for the system to identify the new interfaces..."
	Start-Sleep -Seconds 5

	# Display virtual switch status
	$ManagedVLANs = @()
	ForEach ( $Port in $(Get-VMNetworkAdapterVlan -ManagementOS | Where-Object { $_.ParentAdapter.SwitchName -eq $Switch.Name }) ) {
		$ManagedVLANs += New-Object -Type PSOBJECT -Property @{
			Mode       = $Port.OperationMode
			VLANId     = $Port.AccessVlanId
			PortName   = $Port.ParentAdapter.Name
			MACAddress = $(Get-VMNetworkAdapter -ManagementOS | Where-Object { $_.Name -eq $Port.ParentAdapter.Name } ).MACAddress -replace '..(?!$)', '$&-'
		}
	}
	$ManagedVLANs | Format-Table * -AutoSize

	# Disable all VLANs
	ForEach ($VLAN in $ManagedVLANs) {
		If ($VLAN.VLANId -ne 0) {
			$Decorated = Get-NetAdapter | Where-Object { $_.MACAddress -eq $VLAN.MACAddress } `
			| Rename-NetAdapter -NewName $("Port " + $VLAN.PortName) -PassThru
			
			# Enable adapter to manage routes and remove existing routes
			Enable-NetAdapter -InputObject $Decorated -Confirm:$false | Out-Null
			Get-NetRoute -InterfaceIndex $Decorated.ifIndex | Remove-NetRoute -Confirm:$false

			# Add default routes for VPN Clients
			$Configuration = $RequiredVLANs | Where-Object { $_.ID -eq $VLAN.VLANId }
			ForEach ($Route in $Configuration.Routing) {
				New-NetRoute -DestinationPrefix $Route.Prefix -NextHop $Route.Gateway -InterfaceIndex $Decorated.ifIndex | Out-Null
			}

			Disable-NetAdapter -InputObject $Decorated -Confirm:$false | Out-Null
			Write-Host "VLAN ", $VLAN.VLANId, $("Port " + $VLAN.PortName), "is now disabled."
		}
		Else {
			# Beware: the untagged virtual interface has the same MAC address as the physical interface
			$Decorated = Get-NetAdapter | Where-Object { ($_.MACAddress -eq $VLAN.MACAddress) -and $_.InterfaceDescription.Contains("Hyper-V Virtual Ethernet Adapter") } `
			| Rename-NetAdapter -NewName $($DefaultPhysicalPortName + " " + $VLAN.PortName)
		}
	}

	# Rename the physical port as needed
	Write-Host
	If ($Adapter.Name -ne $DefaultPhysicalPortName) {
		Rename-NetAdapter -InputObject $Adapter -NewName $DefaultPhysicalPortName
	}
	Write-Host "The network adapter has been renamed $DefaultPhysicalPortName."
	Write-Host
}

Write-Host "Routes with a limited lifetime value:"
Write-Host "-------------------------------------"
$Done = $False
Do {
	Try {
		# Wait a few seconds for the system to digest these routes. Why? I still don't know.
		Start-Sleep -Seconds 5
		# Get all routes for this interface
		Get-NetRoute -IncludeAllCompartments -ErrorAction Stop `
		| Where-Object -FilterScript { $_.ValidLifetime -ne ([TimeSpan]::MaxValue) } `
		| Format-Table ifIndex, DestinationPrefix, NextHop, InterfaceAlias, ValidLifetime -AutoSize
		$Done = $True
	}
	Catch {
		Write-Warning "Waiting until routes are available again."
	}
} Until ($Done)

Write-Host

Write-Host "Please review the adapter metric for desired default route. It is typically 25 for a Gigabit adapter"
Write-Host "and the value 10 is suggested if more than one adapter was assigned a default route."
Write-Host
Write-Host "Current default route(s):"
Try {
	$(Find-NetRoute -RemoteIPAddress 0.0.0.0 -ErrorAction Stop )[1] | Format-List InterfaceAlias, InterfaceMetric
}
Catch {
	Write-Warning "None! You may have to wait a few moments ;-)"
}

ncpa.cpl

Pause


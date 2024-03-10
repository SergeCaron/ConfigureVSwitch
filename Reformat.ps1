##******************************************************************
## Release date: 2024.03.10
##
## Copyright (c) 2024 PC-Évolution enr.
## This code is licensed under the GNU General Public License (GPL).
##
## THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
## ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
## IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
## PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
##
##******************************************************************
param (
	[parameter()]
	[switch]$UseCRLF
)

#  Setup the NewLine delimiter
$Delimiter = If ($UseCRLF.IsPresent) { "`r`n" } else { "`n" }

# What are we running ?
$ThisPS = $PSVersionTable.PSVersion.Major.ToString() + "." + $PSVersionTable.PSVersion.Minor.ToString()

$Junk = $ErrorActionPreference # Tuck this away ;-)
$ErrorActionPreference = "Stop"

# Rules definition must be located in the directory containing this script.
$Rules = $(Split-Path -Parent $($script:MyInvocation.InvocationName)) + "\FormattingRules.psd1"

Try {
	# Since we have the tool, validate the rules definitions
	$Health = Invoke-ScriptAnalyzer -Path $Rules

	If ($Null -eq $Health) {
		# OK! we have valid rules: get the target script's filename.
		Add-Type -AssemblyName System.Windows.Forms
		$FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
			# InitialDirectory = [Environment]::GetFolderPath('Desktop') 
			InitialDirectory = $script:MyInvocation.MyCommand.Path
			Filter           = ''
			Title            = 'Please locate your script:'
		}
		$FileBrowser.ShowDialog() | Out-Null

		# Reformat this script :
		If ( ![string]::IsNullOrEmpty($FileBrowser.FileName) ) {
			# Strip line delimiters from the input file and use a uniform convention
			$Script = ($(Get-Content $FileBrowser.FileName -Encoding UTF8) -join $Delimiter) + $Delimiter
			# Reformat the inpt script
			$Revision = Invoke-Formatter -ScriptDefinition $Script -Settings $Rules
			$RevisedScriptName = $($(Split-Path -Parent $FileBrowser.FileName) + "\Reformatted" + $FileBrowser.SafeFileName)

			# Starting from version 6 PowerShell supports the UTF8NoBOM encoding both for "set-content" and "out-file"
			# and uses this as default encoding. In version 5 however, a byte order marker is always inserted.
			# This is the equivalent of 
			#	Out-File -Encoding UTF8NoBOM -FilePath $RevisedScriptName -Force -InputObject $Revision -NoNewLine
			$Output = New-Object Text.UTF8Encoding
			If ($ThisPS -gt "5.1") {
				Set-Content -Path $RevisedScriptName -Force -Value $Output.GetBytes($Revision) -AsByteStream
			}
			Else {
				Set-Content -Path $RevisedScriptName -Force -Value $Output.GetBytes($Revision) -Encoding Byte
			}

			# Windows-oriented file compare : the default dates way back then...
			& "$([System.Environment]::SystemDirectory)\FC.EXE" /A /N /L "$($FileBrowser.FileName)" "$RevisedScriptName"
			Write-Host "Done!"
		}
		else { Write-Warning "No file selected ;)" }
	}
	Else {
		Write-Warning $Health
		Write-Warning "Check formatting rules!"
	}
}
Catch {
	Write-Warning $_.Exception.Message
}
Finally {
	$ErrorActionPreference = $Junk
}

# Wait for the user's acknowledgement if "running with PowerShell"
If ($script:MyInvocation.CommandOrigin -eq "Internal") { Pause }

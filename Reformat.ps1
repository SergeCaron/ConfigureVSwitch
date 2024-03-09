##******************************************************************
## Release date: 2024.03.09
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
			$Script = $(Get-Content $FileBrowser.FileName -Encoding UTF8) -join "`r`n"
			$Revision = Invoke-Formatter -ScriptDefinition $Script -Settings $Rules
			$RevisedScript = $($(Split-Path -Parent $FileBrowser.FileName) + "\Reformatted" + $FileBrowser.SafeFileName)
			Out-File -Encoding UTF8 -FilePath $RevisedScript -Force -InputObject $Revision
			# Windows-oriented file compare : the default dates way back then...
			& "$([System.Environment]::SystemDirectory)\FC.EXE" /A /N /L "$($FileBrowser.FileName)" "$RevisedScript"
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

# Wait for the user's acknowledgement if running directly from terminal
If ($script:MyInvocation.CommandOrigin -eq "RunSpace") { Pause }

# Reformatting PowerShell scripts and data files

## Outside VScode
You may not want to install VSCode just for the purpose of reformatting PowerShell scripts or your VSCode workspace may have implemented a different coding standard than what is expected in this project.
This *Reformat.ps1* script relies on the PSScriptAnalyzer utility module *[PS-ScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules)* to validate and reformat PowerShell scripts.

The utility module is installed in your environment using (you may have to also install the *Nuget* provider):
```
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name PSScriptAnalyzer -Force
```
The formatting rules are defined in the data file *FormattingRules.psd1* and mut be placed in the same directory as the *Reformat.ps1* script. The rules are documented *[here](https://github.com/PowerShell/PSScriptAnalyzer/tree/master/docs/Rules)*.

On entry, the script validates the formatting rules and open a file browser to select what will be reformatted. The output file (if any) is placed in the same directory, implying write access and file creation privileges. The prefix "Reformatted" is added to the original file name.

This is a Windows-oriented script. 
- the input file is presumed coded UTF-8 ad the output file is explicitly coded UTF-8.
- a simple diff between the source and output files shows the first and last lines of any differences: when there are no differences, this serves as a validation that the source script conforms to the formatting rules.

## Inside VSCode
On input, VSCode does not automatically change the file encoding to UTF-8 : see this *[UTF-8 Debugging Chart](https://www.i18nqa.com/debug/utf8-debug.html)* for tell-tale signs of corruption.

The default PowerShell extension in VSCode allows reformatting a document using the Shift+Alt+F command or the *Format Document* context menu. This extension contains a hidden implementation of the PSScriptAnalyzer module which cannot be invoked outside VSCode.

The *Reformat.ps1* script can also run from a VSCode terminal window under the same conditions as outlined in [Outside VSCode](#outside-vscode).

The following VSCode settings for this extension are the equivalen of the formatting rules defined in the data file *FormattingRules.psd1* supplied with this script:

```
{
    "powershell.codeFormatting.autoCorrectAliases": true,
    "powershell.codeFormatting.avoidSemicolonsAsLineTerminators": true,
    "powershell.codeFormatting.pipelineIndentationStyle": "IncreaseIndentationForFirstPipeline",
    "powershell.codeFormatting.preset": "Stroustrup",
    "powershell.codeFormatting.trimWhitespaceAroundPipe": true,
    "powershell.codeFormatting.useCorrectCasing": true,
}
```
VSCode implements a *Compare Selected* in the context menu of the Explorer view. This implies that you save the reformatted text in the same tree just for the purpose of checking code conformity. This condition i the same when using the *Reformat.ps1* script.


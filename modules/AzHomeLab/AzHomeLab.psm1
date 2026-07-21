#Requires -Version 7.0
<#
.SYNOPSIS
    AzHomeLab root module file — dot-sources all Public and Private functions.

.DESCRIPTION
    Loads every function script under .\Public and .\Private and exports only
    the Public functions, per the FunctionsToExport list declared in
    AzHomeLab.psd1. Keeping one function per file (as required by the build
    spec) makes each function easy to locate, test, and review independently.
#>

$publicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

$publicFunctions  = @(Get-ChildItem -Path $publicPath  -Filter '*.ps1' -ErrorAction SilentlyContinue)
$privateFunctions = @(Get-ChildItem -Path $privatePath -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($function in @($publicFunctions + $privateFunctions)) {
    try {
        . $function.FullName
    }
    catch {
        Write-Error "AzHomeLab module: failed to dot-source '$($function.FullName)'. Error: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFunctions.BaseName

[CmdletBinding()]
Param(
	[String]$version,
  [String]$collection = 'puppet',
  [String]$absolute_source,
  [String]$windows_source = 'https://downloads.puppet.com',
  [String]$install_options = 'REINSTALLMODE="amus"',
  [Bool]$stop_service = $False
)
# If an error is encountered, the script will stop instead of the default of "Continue"
$ErrorActionPreference = "Stop"

try {
  if ((Get-WmiObject Win32_OperatingSystem).OSArchitecture -match '^32') {
      $arch = "x86"
  } else {
      $arch = "x64"
  }
}
catch [System.Management.Automation.CommandNotFoundException] {
  if (((Get-CimInstance -ClassName win32_OperatingSystem).OSArchitecture) -eq '64-bit') {
    $arch = "x64"
  } else {
    $arch = "x86"
  }
}

function Test-PuppetInstalled {
  $rootPath = 'HKLM:\SOFTWARE\Puppet Labs\Puppet'
  try { 
    if (Get-ItemProperty -Path $rootPath) { RETURN $true }
  }
  catch {
    RETURN $false
  }
}

if ($version) {
    if ($version -eq "latest") {
      $msi_name = "puppet-agent-${arch}-latest.msi"
    } else {
      $msi_name = "puppet-agent-${version}-${arch}.msi"
    }
}
else {
    if (Test-PuppetInstalled) {
      Write-Output "Puppet Agent detected and no version specified. Nothing to do."
      Exit
    }

    $msi_name = "puppet-agent-${arch}-latest.msi"
}

# Change windows_source only if the collection is a nightly build, and the source was not explicitly specified.
if (($collection -like '*nightly*') -And -Not ($PSBoundParameters.ContainsKey('windows_source'))) {
  $windows_source = 'https://nightlies.puppet.com/downloads'
}

if ($absolute_source) {
    $msi_source = "$absolute_source"
}
else {
    $msi_source = "$windows_source/windows/${collection}/${msi_name}"
}

$date_time_stamp = (Get-Date -format s) -replace ':', '-'
$msi_dest = Join-Path ([System.IO.Path]::GetTempPath()) "puppet-agent-$arch.msi"
$install_log = Join-Path ([System.IO.Path]::GetTempPath()) "$date_time_stamp-puppet-install.log"

function DownloadPuppet {
  Write-Verbose "Downloading the Puppet Agent for Puppet Enterprise on $env:COMPUTERNAME..."

  $webclient = New-Object system.net.webclient

  try {
    $webclient.DownloadFile($msi_source,$msi_dest)
  }
  catch [System.Net.WebException] {
    # If we can't find the msi, then we may not be configured correctly
    if($_.Exception.Response.StatusCode -eq [system.net.httpstatuscode]::NotFound) {
        Throw "Failed to download the Puppet Agent installer: $msi_source"
    }
    # Throw all other WebExceptions
    Throw $_
  }
}

function InstallPuppet {
  $msiexec_args = "/qn /log $install_log /i $msi_dest /norestart $install_options"
  Write-Output "Installing the Puppet Agent on $env:COMPUTERNAME..."
  $msiexec_proc = [System.Diagnostics.Process]::Start('msiexec', $msiexec_args)
  $msiexec_proc.WaitForExit()
  if (@(0, 1641, 3010) -NotContains $msiexec_proc.ExitCode) {
    Throw "Installation Failed on: $env:COMPUTERNAME. Exit code: " + $msiexec_proc.ExitCode + " Install Log: $install_log"
  }
}

function Cleanup {
    if($stop_service -eq 'true') {
      C:\"Program Files"\"Puppet Labs"\Puppet\bin\puppet resource service puppet ensure=stopped enable=false
    }
    Write-Output "Deleting $msi_dest and $install_log"
    Remove-Item -Force $msi_dest
    Remove-Item -Force $install_log
}

DownloadPuppet
InstallPuppet
Cleanup

Write-Output "Puppet Agent installed on $env:COMPUTERNAME"

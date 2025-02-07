[CmdletBinding()]
Param(
	[String]$version,
  [String]$collection = 'puppet',
  [String]$absolute_source,
  [String]$windows_source = 'https://downloads.puppet.com',
  [String]$install_options = 'REINSTALLMODE="amus"',
  [Bool]$stop_service = $False,
  [Int]$retry = 5,
  [Bool]$_noop = $False
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

function Test-PuppetInstalledVersion {
  $rootPath = 'HKLM:\SOFTWARE\Puppet Labs\Puppet'

  $reg = Get-ItemProperty -Path $rootPath -ErrorAction SilentlyContinue
  if ($null -ne $reg) {
    if ($null -ne $reg.RememberedInstallDir64) {
      $loc = $reg.RememberedInstallDir64+'VERSION'
    } elseif ($null -ne $reg.RememberedInstallDir) {
      $loc = $reg.RememberedInstallDir+'VERSION'
    }
  }

  if ($null -ne $loc) {
    $installedVersion = Get-Content -Path $loc -ErrorAction SilentlyContinue
    if ($installedVersion -eq $version) {
      RETURN $true
    }
  }

  RETURN $false
}

function Test-RunningServices {
  $puppetAgentService = Get-Service -DisplayName 'Puppet Agent' -ErrorAction SilentlyContinue
  $pxpAgentService = Get-Service -DisplayName 'Puppet PXP Agent' -ErrorAction SilentlyContinue

  if ($puppetAgentService.Status -eq 'Running' -or $pxpAgentService.Status -eq 'Running') {
    RETURN $true
  }

  RETURN $false
}

if ($version) {
    if (Test-PuppetInstalledVersion) {
      Write-Output "Puppet Agent ${version} detected. Nothing to do."
      Exit
    }

    if ($version -eq "latest") {
      $msi_name = "puppet-agent-${arch}-latest.msi"
    } else {
      $msi_name = "puppet-agent-${version}-${arch}.msi"
    }
}
else {
    if (Test-PuppetInstalledVersion) {
      Write-Output "Version parameter not defined and agent detected. Nothing to do."
      Exit
    }

    $msi_name = "puppet-agent-${arch}-latest.msi"
}

if (Test-RunningServices) {
  Write-Error "Puppet Agent upgrade cannot be done while Puppet services are still running."
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

# Most modern sites either require or are starting to require TLS 1.2.
# On older Windows systems the default security protocols for PowerShell 5 are SSL3 and TLS 1.0.
# When communicating with a site that has a higher TLS requirement requests will fail with the following error:
# `Could not create SSL/TLS secure channel`.`
# Set-Tls12 will add TLS 1.2 to the list of available security protocols if it is not already present.
function Set-Tls12 {
  $Tls12 = [System.Net.SecurityProtocolType]::Tls12
  $CurrentSecurityProtocolList = [System.Net.ServicePointManager]::SecurityProtocol
  if (!$CurrentSecurityProtocolList.HasFlag($Tls12)) {
    [System.Net.ServicePointManager]::SecurityProtocol = $CurrentSecurityProtocolList, [System.Net.SecurityProtocolType]::Tls12
  }
}

function DownloadPuppet {
  Write-Output "Downloading the Puppet Agent installer on $env:COMPUTERNAME..."
  Set-Tls12

  $webclient = New-Object system.net.webclient

  try {
    $webclient.DownloadFile($msi_source,$msi_dest)
  }
  catch [System.Net.WebException] {
    For ($attempt_number = 1; $attempt_number -le $retry; $attempt_number++) {
      try {
        Write-Output "Retrying... [$attempt_number/$retry]"
        $webclient.DownloadFile($msi_source,$msi_dest)
        break
      }
      catch [System.Net.WebException] {
        if($attempt_number -eq $retry) {
          # If we can't find the msi, then we may not be configured correctly
          if($_.Exception.Response.StatusCode -eq [system.net.httpstatuscode]::NotFound) {
            Throw "Failed to download the Puppet Agent installer: $msi_source"
          }

          # Throw all other WebExceptions
          Throw $_
        }
        Start-Sleep -s 1
      }
    }
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

if($_noop -eq 'true') {
  Exit
} else {
  DownloadPuppet
  InstallPuppet
  Cleanup
  Write-Output "Puppet Agent installed on $env:COMPUTERNAME"
}

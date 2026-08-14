$ErrorActionPreference = "Stop"

$launcherPath = $PSScriptRoot
$runScript = Join-Path $launcherPath "run.cmd"

Write-Host "Installing H8 Launcher..."
Write-Host ""

# Check that the Windows wrapper exists:
if (-not (Test-Path $runScript)) {
	Write-Error "run.cmd was not found in: $launcherPath"
	exit 1
}

# Check that Perl is available:
if (-not (Get-Command perl -ErrorAction SilentlyContinue)) {
	Write-Error "Perl was not found in your PATH. Please install Perl and try again."
	exit 1
}

# Get the current user PATH:
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

# Add the launcher directory if it is not already present:
$pathEntries = @()

if ($userPath) {
	$pathEntries = $userPath -split ';' | Where-Object { $_ -ne "" }
}

if ($pathEntries -notcontains $launcherPath) {
	$newUserPath = ($pathEntries + $launcherPath) -join ';'
	[Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
	Write-Host "Added H8 Launcher to your user PATH."
} else {
	Write-Host "H8 Launcher is already in your user PATH."
}

Write-Host ""
Write-Host "Installation complete!"
Write-Host ""
Write-Host "Restart your terminal, then run:"
Write-Host ""
Write-Host " run"
Write-Host ""

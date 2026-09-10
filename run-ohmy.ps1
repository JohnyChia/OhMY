<#
.SYNOPSIS
Starts the complete ohMY Android development stack.

.EXAMPLE
.\run-ohmy.ps1
Starts Maps/recommendations, AI chat/voice, reuses or boots Pixel 9, forwards
ports, and launches Flutter.

.EXAMPLE
.\run-ohmy.ps1 -ColdBoot
Cold boots Pixel 9 before launching the stack.

.EXAMPLE
.\run-ohmy.ps1 -Emulator Pixel_7_API_34 -ColdBoot
Uses the installed Pixel 7 AVD.

.EXAMPLE
.\run-ohmy.ps1 -InstallDependencies
Installs Node/Flutter-adjacent service dependencies and prepares the optional
Verified Traveller Python environment before launching.

.EXAMPLE
.\run-ohmy.ps1 -Device PHONE_SERIAL
Uses a USB-debuggable Android phone and configures adb reverse forwarding.
#>
[CmdletBinding()]
param(
    [string]$Device = 'emulator-5554',
    [string]$Emulator = 'Pixel_9_API_34',
    [switch]$ColdBoot,
    [switch]$InstallDependencies,
    [switch]$SkipVerification
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendRoot = Join-Path $projectRoot 'CD\backend'
$flutterApp = Join-Path $projectRoot 'CD\flutter_app'
$chatbotRoot = Join-Path $backendRoot 'modules\ai_chatbot'
$verifiedRoot = Join-Path $backendRoot 'modules\verified_traveller'
$backendEnvFile = Join-Path $backendRoot '.env'
$chatbotEnvFile = Join-Path $chatbotRoot '.env'
$verifiedEnvFile = Join-Path $verifiedRoot '.env'
$androidLocalProperties = Join-Path $flutterApp 'android\local.properties'
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adbExe = Join-Path $androidSdk 'platform-tools\adb.exe'
$emulatorExe = Join-Path $androidSdk 'emulator\emulator.exe'
$script:startedProcesses = @()

function Resolve-CommandPath([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "$Name was not found. Install it or add it to PATH."
    }
    return $command.Source
}

function Read-EnvFile([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) { continue }
        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
        $values[$key] = $value
    }
    return $values
}

function Test-ConfiguredValue([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value) -and
        $Value -notmatch '^(YOUR_|your_|replace-with)'
}

function Assert-ConfiguredValues(
    [hashtable]$Values,
    [string[]]$RequiredKeys,
    [string]$Description
) {
    $missing = @(
        foreach ($key in $RequiredKeys) {
            if (-not $Values.ContainsKey($key) -or
                -not (Test-ConfiguredValue "$($Values[$key])")) {
                $key
            }
        }
    )
    if ($missing.Count -gt 0) {
        throw "$Description is missing: $($missing -join ', ')."
    }
}

function Test-PortListening([int]$Port) {
    return [bool](
        Get-NetTCPConnection -LocalPort $Port -State Listen `
            -ErrorAction SilentlyContinue
    )
}

function Wait-Port([int]$Port, [int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-PortListening $Port) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Get-AdbDeviceState([string]$TargetDevice) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        return "$(& $adbExe -s $TargetDevice get-state 2>$null)".Trim()
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Start-BackgroundService(
    [string]$Name,
    [int]$Port,
    [string]$Executable,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [hashtable]$Environment = @{}
) {
    if (Test-PortListening $Port) {
        Write-Host "[skip] $Name is already listening on port $Port" `
            -ForegroundColor Yellow
        return
    }

    $originalEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $originalEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, $Environment[$key])
    }

    try {
        $serviceProcess = Start-Process `
            -FilePath $Executable `
            -ArgumentList $Arguments `
            -WorkingDirectory $WorkingDirectory `
            -WindowStyle Hidden `
            -PassThru
        $script:startedProcesses += $serviceProcess
    } finally {
        foreach ($key in $originalEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable(
                $key,
                $originalEnvironment[$key]
            )
        }
    }

    if (-not (Wait-Port $Port)) {
        throw "$Name did not start on port $Port. Check its .env configuration."
    }
    Write-Host "[ok]   $Name on port $Port (pid $($serviceProcess.Id))" `
        -ForegroundColor Green
}

function Install-NodeDependencies(
    [string]$Name,
    [string]$Directory,
    [string]$NpmExecutable
) {
    $modules = Join-Path $Directory 'node_modules'
    if (-not $InstallDependencies -and (Test-Path -LiteralPath $modules)) {
        return
    }
    Write-Host "[setup] Installing $Name dependencies" -ForegroundColor Cyan
    Push-Location $Directory
    try { & $NpmExecutable install } finally { Pop-Location }
}

function Wait-AndroidBoot([string]$TargetDevice, [int]$TimeoutSeconds = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = Get-AdbDeviceState $TargetDevice
        if ($state -eq 'device') {
            $bootCompleted = & $adbExe -s $TargetDevice shell getprop sys.boot_completed 2>$null
            if ("$bootCompleted".Trim() -eq '1') { return $true }
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Stop-StartedServices {
    foreach ($serviceProcess in $script:startedProcesses) {
        Stop-Process -Id $serviceProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($script:startedProcesses.Count -gt 0) {
        Write-Host '=== stopped launcher-owned services ===' -ForegroundColor Magenta
    }
}

try {
if (-not (Test-Path -LiteralPath $adbExe)) {
    throw "adb was not found at $adbExe. Install Android SDK Platform-Tools."
}
if (-not (Test-Path -LiteralPath $emulatorExe)) {
    throw "Android Emulator was not found at $emulatorExe."
}

$flutterExe = Resolve-CommandPath 'flutter'
$nodeExe = Resolve-CommandPath 'node'
$npmExe = Resolve-CommandPath 'npm.cmd'

if (-not (Test-Path -LiteralPath $backendEnvFile)) {
    Copy-Item (Join-Path $backendRoot '.env.example') $backendEnvFile
    throw "Created $backendEnvFile. Add the required keys, then run this script again."
}
if (-not (Test-Path -LiteralPath $androidLocalProperties)) {
    Copy-Item `
        (Join-Path $flutterApp 'android\local.properties.example') `
        $androidLocalProperties
    throw "Created $androidLocalProperties. Add MAPS_API_KEY and SDK paths, then run again."
}

$backendEnvironment = Read-EnvFile $backendEnvFile
$androidProperties = Read-EnvFile $androidLocalProperties
Assert-ConfiguredValues $backendEnvironment @(
    'GOOGLE_PLACES_API_KEY',
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'SUPABASE_SERVICE_ROLE_KEY',
    'GROQ_API_KEY_1',
    'GROQ_MODEL'
) 'CD\backend\.env'
$androidMapsKey = $androidProperties['MAPS_API_KEY']
if (-not (Test-ConfiguredValue "$androidMapsKey")) {
    $androidMapsKey = $backendEnvironment['MAPS_API_KEY']
}
if (-not (Test-ConfiguredValue "$androidMapsKey")) {
    throw 'MAPS_API_KEY is missing from both Android local.properties and backend .env.'
}

Install-NodeDependencies 'recommendation backend' $backendRoot $npmExe
Install-NodeDependencies 'AI chatbot' $chatbotRoot $npmExe
if ($InstallDependencies -or
    -not (Test-Path -LiteralPath (Join-Path $flutterApp '.dart_tool\package_config.json'))) {
    Write-Host '[setup] Installing Flutter dependencies' -ForegroundColor Cyan
    Push-Location $flutterApp
    try { & $flutterExe pub get } finally { Pop-Location }
}

Write-Host '=== ohMY launcher ===' -ForegroundColor Magenta

$isEmulator = $Device -like 'emulator-*'
if ($isEmulator) {
    $deviceState = Get-AdbDeviceState $Device
    if ($ColdBoot -and $deviceState -eq 'device') {
        Write-Host "[boot] Stopping $Device for a cold boot" -ForegroundColor Cyan
        & $adbExe -s $Device emu kill | Out-Null
        Start-Sleep -Seconds 3
        $deviceState = ''
    }

    if ($deviceState -ne 'device') {
        $availableAvds = @(& $emulatorExe -list-avds)
        if ($Emulator -notin $availableAvds) {
            throw "AVD '$Emulator' was not found. Available: $($availableAvds -join ', ')"
        }
        $emulatorArguments = @('-avd', $Emulator)
        if ($ColdBoot) { $emulatorArguments += '-no-snapshot-load' }
        Write-Host "[boot] Launching $Emulator" -ForegroundColor Cyan
        Start-Process -FilePath $emulatorExe -ArgumentList $emulatorArguments
    } else {
        Write-Host "[ok]   $Device is already running" -ForegroundColor Green
    }
}

Write-Host "[wait] Waiting for $Device to finish booting" -ForegroundColor Cyan
if (-not (Wait-AndroidBoot $Device)) {
    throw "$Device did not become ready within 180 seconds."
}
Write-Host "[ok]   $Device is ready" -ForegroundColor Green

Start-BackgroundService `
    'Recommendation and Maps backend' 3000 $nodeExe @('server.js') `
    $backendRoot

$chatbotEnvironment = @{}
foreach ($key in @(
    'PORT',
    'GROQ_API_KEY_1',
    'GROQ_API_KEY_2',
    'GROQ_MODEL',
    'WHISPER_PROMPT',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY'
)) {
    if ($backendEnvironment.ContainsKey($key)) {
        $chatbotEnvironment[$key] = $backendEnvironment[$key]
    }
}
$chatbotEnvironment['PORT'] = '3001'
if (Test-Path -LiteralPath $chatbotEnvFile) {
    foreach ($entry in (Read-EnvFile $chatbotEnvFile).GetEnumerator()) {
        $chatbotEnvironment[$entry.Key] = $entry.Value
    }
}
Start-BackgroundService `
    'Nova AI chatbot and voice transcription' 3001 $nodeExe @('server.js') `
    $chatbotRoot $chatbotEnvironment

$verificationStarted = $false
if (-not $SkipVerification) {
    $venvPython = Join-Path $verifiedRoot '.venv\Scripts\python.exe'
    if ($InstallDependencies -and -not (Test-Path -LiteralPath $verifiedEnvFile)) {
        Copy-Item (Join-Path $verifiedRoot '.env.example') $verifiedEnvFile
        Write-Host `
            '[setup] Created Verified Traveller .env; add its secrets to enable the service.' `
            -ForegroundColor Yellow
    }
    if ($InstallDependencies -and -not (Test-Path -LiteralPath $venvPython)) {
        Write-Host '[setup] Creating Verified Traveller Python environment' `
            -ForegroundColor Cyan
        $pythonLauncher = Resolve-CommandPath 'python'
        & $pythonLauncher -m venv (Join-Path $verifiedRoot '.venv')
        & $venvPython -m pip install -r (Join-Path $verifiedRoot 'requirements.txt')
        & $venvPython (Join-Path $verifiedRoot 'setup_models.py')
    }

    if ((Test-Path -LiteralPath $venvPython) -and
        (Test-Path -LiteralPath $verifiedEnvFile)) {
        Start-BackgroundService `
            'Verified Traveller backend' 8000 $venvPython `
            @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000') `
            $verifiedRoot
        $verificationStarted = $true
    } else {
        Write-Host `
            '[skip] Verified Traveller is not configured. Use -InstallDependencies after creating its .env.' `
            -ForegroundColor DarkYellow
    }
}

foreach ($port in @(3000, 3001)) {
    & $adbExe -s $Device reverse "tcp:$port" "tcp:$port" | Out-Null
}
if ($verificationStarted -or (Test-PortListening 8000)) {
    & $adbExe -s $Device reverse tcp:8000 tcp:8000 | Out-Null
}
Write-Host '[ok]   Android port forwarding configured' -ForegroundColor Green

$flutterArguments = @(
    'run',
    '-d', $Device,
    "--dart-define=SUPABASE_URL=$($backendEnvironment['SUPABASE_URL'])",
    "--dart-define=SUPABASE_ANON_KEY=$($backendEnvironment['SUPABASE_ANON_KEY'])",
    '--dart-define=BACKEND_URL=http://127.0.0.1:3000',
    '--dart-define=AI_CHATBOT_URL=http://127.0.0.1:3001',
    '--dart-define=VERIFICATION_API_URL=http://127.0.0.1:8000',
    '--dart-define=NAVIGATION_SIMULATION=true'
)

Write-Host '[go]   Launching Flutter. Press q to stop the app and launcher-owned services.' `
    -ForegroundColor Magenta
$previousMapsApiKey = [Environment]::GetEnvironmentVariable('MAPS_API_KEY')
[Environment]::SetEnvironmentVariable('MAPS_API_KEY', $androidMapsKey)
Push-Location $flutterApp
try {
    & $flutterExe @flutterArguments
} finally {
    Pop-Location
    [Environment]::SetEnvironmentVariable('MAPS_API_KEY', $previousMapsApiKey)
}
} finally {
    Stop-StartedServices
}

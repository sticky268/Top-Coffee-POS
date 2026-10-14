param(
    [string]$Flutter = "C:\Flutter\flutter\bin\flutter.bat",
    [string]$Adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
)
$ErrorActionPreference = "Stop"
$frontend = Split-Path $PSScriptRoot -Parent
$email = Read-Host "Rehearsal account email"
$password = Read-Host "Password (hidden)" -AsSecureString
$credential = New-Object System.Net.NetworkCredential("", $password)
$body = @{ email = $email; password = $credential.Password; device_name = "rehearsal-emulator" } | ConvertTo-Json -Compress
try {
    $login = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8001/api/v1/auth/login" -ContentType "application/json" -Body $body
} finally {
    $body = $null
    $credential = $null
    $password = $null
}
if (-not $login.data.token) { throw "Rehearsal backend did not return a session token." }
$handoff = [guid]::NewGuid().ToString("N")
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("pos-session-" + $handoff + ".json")
$remote = "/data/local/tmp/pos-session-" + $handoff + ".json"
$session = @{ handoff_id = $handoff; token = $login.data.token } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($temporary, $session, (New-Object System.Text.UTF8Encoding($false)))
$session = $null
$login = $null
$job = $null
$sent = $false
try {
    $job = Start-Job -ArgumentList $frontend, $Flutter, $handoff -ScriptBlock {
        param($directory, $flutterPath, $requestId)
        Set-Location $directory
        & $flutterPath test integration_test/operations_readonly_smoke_test.dart -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8001/api/v1 --dart-define=REHEARSE_OFFLINE=true "--dart-define=LOGIN_HANDOFF_ID=$requestId" 2>&1 | ForEach-Object { "$_" }
        Write-Output "FLUTTER_EXIT_CODE=$LASTEXITCODE"
    }
    $deadline = (Get-Date).AddMinutes(12)
    while ($job.State -eq "Running") {
        Receive-Job $job -ErrorAction Continue
        if ((Get-Date) -gt $deadline) { throw "Timed out waiting for the emulator test." }
        if (-not $sent) {
            $ErrorActionPreference = "Continue"
            $marker = (& $Adb -s emulator-5554 shell run-as com.example.top_coffee_pos cat files/rehearsal-session-request 2>$null | Out-String).Trim()
            if ($marker -eq $handoff) {
                & $Adb -s emulator-5554 push $temporary $remote 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Could not transfer the local session." }
                & $Adb -s emulator-5554 shell run-as com.example.top_coffee_pos cp $remote files/rehearsal-session.json 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "Could not place the session in the test app." }
                & $Adb -s emulator-5554 shell rm -f $remote 2>&1 | Out-Null
                Remove-Item -LiteralPath $temporary -Force
                $sent = $true
                Write-Output "Session delivered to emulator; automatic login will continue."
            }
            $ErrorActionPreference = "Stop"
        }
        Start-Sleep -Milliseconds 500
    }
    Receive-Job $job -ErrorAction Continue
    if ($job.State -eq "Failed") { throw "The Flutter test process failed." }
} finally {
    if ($job) {
        if ($job.State -eq "Running") { Stop-Job $job }
        Remove-Job $job -Force
    }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    $ErrorActionPreference = "Continue"
    & $Adb -s emulator-5554 shell rm -f $remote 2>&1 | Out-Null
    & $Adb -s emulator-5554 shell run-as com.example.top_coffee_pos rm -f files/rehearsal-session.json files/rehearsal-session-request 2>&1 | Out-Null
}

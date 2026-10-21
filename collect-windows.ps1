# 솔루션 찾는 법 case별 명령 결과를 ${hostname}-${case}.txt 로 저장 (Windows)
# 사용: powershell -ExecutionPolicy Bypass -File collect-windows.ps1 [-Out 출력폴더]   (기본: 현재 폴더)
param([string]$Out = '.')

$h = $env:COMPUTERNAME
New-Item -ItemType Directory -Force $Out | Out-Null

function Save($name, [scriptblock]$block) {
    $f = Join-Path $Out "$h-$name.txt"
    $body = & $block | Out-String -Width 300
    ("# $h $name " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n`r`n" + $body) | Out-File -FilePath $f -Encoding utf8
    "saved $f"
}

Save 'cron' {
    Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' } |
        Select-Object TaskPath, TaskName, State, @{n='Run';e={($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join '; '}} |
        Format-Table -AutoSize
}

Save 'listen' {
    Get-NetTCPConnection -State Listen | ForEach-Object {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)"
        [pscustomobject]@{ Host=$env:COMPUTERNAME; Process=$p.Name; Started=$p.CreationDate.ToString('yyyy-MM-dd'); PID=$p.ProcessId; Port=$_.LocalPort; Path=$p.ExecutablePath; Args=$p.CommandLine }
    } | Sort-Object Port, PID -Unique | Format-Table -AutoSize
}

Save 'process' {
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -notlike 'C:\Windows\*' } |
        Select-Object Name, ProcessId, CreationDate, ExecutablePath, CommandLine | Sort-Object CreationDate |
        Format-Table -AutoSize
}

Save 'installed' {
    '## 자동 시작인데 꺼진 서비스'
    Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Format-Table -AutoSize
    '## Windows 밖 경로의 서비스'
    Get-CimInstance Win32_Service | Where-Object { $_.PathName -notlike '*\Windows\*' } |
        Select-Object Name, State, StartMode, StartName, PathName | Format-Table -AutoSize
    '## 설치된 프로그램'
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object DisplayName | Select-Object DisplayName, InstallDate, InstallLocation | Format-Table -AutoSize
}

Save 'container' { 'Windows: Docker 없음, 해당 없음' }

# 한 파일로 압축 (내려받기용)
$zip = Join-Path $Out "$h-solution.zip"
Compress-Archive -Path (Join-Path $Out "$h-*.txt") -DestinationPath $zip -Force
"archive: $((Resolve-Path $zip).Path)"

# 솔루션 찾는 법 (case별)

OS별로 나눈다. 기본 case는 crontab(예약), 포트를 여는 프로세스, 포트 없이 떠 있는 것, 설치만 되어 있고 꺼진 것, 컨테이너.

- [Linux (Ubuntu)](#linux-ubuntu)
- [Windows (PowerShell)](#windows-powershell)

---

# Linux (Ubuntu)

## Case 1. crontab (시간이 되면 실행, 평소엔 안 떠 있음)

```
crontab -l ; sudo ls /var/spool/cron/crontabs
grep -v -E '^\s*(#|$)' /etc/crontab /etc/cron.d/*
systemctl list-timers --all
```

## Case 2. lsof (포트를 여는 프로세스)

```
sudo lsof -nP -iTCP -sTCP:LISTEN
```

PID와 포트가 나온다. PID로 실행 계정, 시작 시각, 명령줄, 실행 위치를 본다.

```
ps -o user,lstart,args -p <PID>
sudo readlink /proc/<PID>/cwd
```

## Case 3. 포트 없이 떠 있는 프로세스

```
ps -eo user,pid,lstart,args --sort=start_time | grep -v ' \['
```

경로가 `/opt`, `/home`, `/srv`, `/usr/local` 아래이고 `root`가 아닌 전용 계정이면 후보.

## Case 4. 설치만 되어 있고 꺼진 것

```
ls -lt /opt /srv /usr/local /home
apt-mark showmanual
systemctl list-unit-files --type=service --state=enabled | grep -v -E 'ubuntu|systemd|snap'
```

## Case 5. 컨테이너

```
docker ps -a                           # -a: 종료된 컨테이너 포함
docker top <컨테이너>                  # 컨테이너 안 프로세스 목록
docker inspect <컨테이너> --format '{{.Config.Image}} {{.Config.Cmd}}'
docker exec -it <컨테이너> bash        # 접속 (bash가 없으면 sh)
```

- 접속 후 `ps -ef`가 없으면 `cat /proc/1/cmdline | tr '\0' ' '`로 메인 프로세스를 본다.
- 종료된 컨테이너는 `exec`가 안 된다. `docker logs <컨테이너>`로 본다.
- 호스트 기준 PID: `docker inspect -f '{{.State.Pid}}' <컨테이너>`

## 후보를 찾은 뒤

```
sudo lsof -p <PID> | head        # 열린 파일, 로그 위치
df -hT                           # 어느 파일시스템에 있는지
```

이름이 정해지면 같은 이름으로 다른 서버들도 확인한다.

## 참고. 통합 보기 (트리 + 계정 + 날짜 + 포트)

전체 프로세스를 트리로 보여주고, 리슨 포트가 있으면 같은 줄에 붙인다. 포트가 없으면 `-`.
컬럼: `HOST USER PID STARTED PORT PROCESS`

```
awk -v h="$(hostname)" '
BEGIN{split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec",m," "); for(i=1;i<=12;i++)mn[m[i]]=sprintf("%02d",i)}
FILENAME==ARGV[1]{p[$1]=($1 in p)?p[$1]","$2:$2;next}
FNR==1{next}
{pid=substr($0,1,7)+0; u=substr($0,9,12); split(substr($0,22,25),d," "); a=substr($0,48)
 if(a ~ /^[ |\\_+-]*\[/)next
 gsub(/ +$/,"",u)
 printf "%s\t%s\t%s\t%s-%s-%02d\t%s\t%s\n",h,u,pid,d[5],mn[d[2]],d[3],(pid in p)?p[pid]:"-",a}
' <(sudo lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1{n=$9;sub(/.*:/,"",n);print $2,n}' | sort -u) <(ps -eo pid:7,user:12,lstart:25,args --forest) | (echo -e "HOST\tUSER\tPID\tSTARTED\tPORT\tPROCESS"; cat) | column -t -s $'\t'
```

출력 예시:

```
HOST      USER     PID   STARTED     PORT    PROCESS
web-prd1  root     812   2026-10-20  22      sshd: /usr/sbin/sshd -D
web-prd1  root     1310  2026-10-20  80,443  nginx: master process /usr/sbin/nginx
web-prd1  www-data 1311  2026-10-20  -        \_ nginx: worker process
web-prd1  tomcat   1204  2026-10-20  8080    /opt/app/jdk/bin/java -jar /opt/app/app.jar
web-prd1  appuser  1388  2026-10-20  -       python3 /opt/app/worker/run.py
```

- `\_`는 위 줄 프로세스의 자식. 트리 순서라서 시작 시각 순은 아니다.
- bash 전용(`<( )` 사용). 다른 계정 프로세스의 포트까지 보려면 `sudo` 필요.

---

# Windows (PowerShell)

관리자 권한 PowerShell에서 실행하는 것을 권한다. 일반 권한이면 일부 프로세스의 경로, 명령줄이 비어 있다.

## Case 1. 예약 작업 (crontab 대응)

`\Microsoft\*` 아래는 OS 기본이라 뺀다.

```
Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' } |
  Select-Object TaskPath, TaskName, State, @{n='Run';e={($_.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join '; '}}
```

## Case 2. 포트를 여는 프로세스 (lsof 대응)

포트, 프로세스명, 시작 날짜, PID, 실행 파일, 명령줄을 한 표로.

```
Get-NetTCPConnection -State Listen | ForEach-Object {
  $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)"
  [pscustomobject]@{ Host=$env:COMPUTERNAME; Process=$p.Name; Started=$p.CreationDate.ToString('yyyy-MM-dd'); PID=$p.ProcessId; Port=$_.LocalPort; Path=$p.ExecutablePath; Args=$p.CommandLine }
} | Sort-Object Port, PID -Unique | Format-Table -AutoSize
```

실행 계정: `(Get-Process -Id <PID> -IncludeUserName).UserName` (관리자 권한 필요).

## Case 3. 포트 없이 떠 있는 프로세스

`C:\Windows` 밖의 경로(`C:\Program Files`, `D:\`, 사용자 폴더)가 후보.

```
Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -notlike 'C:\Windows\*' } |
  Select-Object Name, ProcessId, CreationDate, ExecutablePath, CommandLine | Sort-Object CreationDate
```

## Case 4. 설치만 되어 있고 꺼진 것

서비스의 `StartName`이 실행 계정, `PathName`이 실행 파일 위치.

```
Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
Get-CimInstance Win32_Service | Where-Object { $_.PathName -notlike '*\Windows\*' } | Select-Object Name, State, StartMode, StartName, PathName
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, InstallDate, InstallLocation
```

## Case 5. 컨테이너

Docker가 없으므로 해당 없음.

## 후보를 찾은 뒤

```
Get-Process -Id <PID> -Module | Select-Object -First 10      # 로드한 파일
Get-PSDrive -PSProvider FileSystem                            # 드라이브
```

이름이 정해지면 같은 이름으로 다른 서버들도 확인한다.

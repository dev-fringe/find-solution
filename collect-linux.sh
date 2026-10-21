#!/bin/bash
# 솔루션 찾는 법 case별 명령 결과를 ${hostname}-${case}.txt 로 저장 (Ubuntu / Linux)
# 사용: bash collect-linux.sh [출력폴더]   (기본: 현재 폴더)

H=$(hostname 2>/dev/null || uname -n)
OUT=${1:-.}
mkdir -p "$OUT"

S=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  S="sudo"
fi

OS_INFO=$(grep -E '^(PRETTY_NAME|NAME|VERSION)=' /etc/os-release 2>/dev/null | head -n 2 | tr '\n' ' ')
[ -z "$OS_INFO" ] && OS_INFO=$(uname -srm 2>/dev/null)

run() {  # run <case명> <명령...>
  name=$1; shift
  f="$OUT/$H-$name.txt"
  {
    echo "# $H $name $(date '+%F %T')"
    echo "# OS: $OS_INFO"
    echo
    "$@"
  } > "$f" 2>&1
  echo "saved $f"
}

case_cron() {
  echo "## crontab (현재 계정)"
  if command -v crontab >/dev/null 2>&1; then
    crontab -l 2>&1
  else
    echo "crontab 명령어 없음"
  fi

  echo; echo "## 계정별 crontab 파일"
  if [ -d /var/spool/cron/crontabs ]; then
    $S ls -la /var/spool/cron/crontabs 2>&1
  elif [ -d /var/spool/cron ]; then
    $S ls -la /var/spool/cron 2>&1
  else
    echo "crontab 저장 디렉토리 없음"
  fi

  echo; echo "## /etc/crontab 및 /etc/cron.d"
  cron_files=()
  [ -f /etc/crontab ] && cron_files+=(/etc/crontab)
  for cf in /etc/cron.d/*; do
    [ -f "$cf" ] && cron_files+=("$cf")
  done
  if [ ${#cron_files[@]} -gt 0 ]; then
    grep -H -v -E '^\s*(#|$)' "${cron_files[@]}" 2>&1
  else
    echo "등록된 cron 파일 없음"
  fi

  echo; echo "## /etc/cron.{hourly,daily,weekly,monthly} 디렉토리 목록"
  has_cron_dir=0
  for cd_dir in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
    if [ -d "$cd_dir" ]; then
      ls -la "$cd_dir" 2>&1
      echo
      has_cron_dir=1
    fi
  done
  [ "$has_cron_dir" -eq 0 ] && echo "해당 디렉토리 없음"

  echo; echo "## systemd timers"
  if [ -d /run/systemd/system ]; then
    systemctl list-timers --all 2>&1
  else
    echo "systemd 미사용 환경 (PID 1이 systemd가 아님)"
  fi

  if command -v atq >/dev/null 2>&1; then
    echo; echo "## at 작업 대기열"
    $S atq 2>&1
  fi
}

case_listen() {
  has_tool=0
  if command -v ss >/dev/null 2>&1; then
    echo "## ss -ltnp (TCP 리슨 포트)"
    $S ss -ltnp 2>&1
    has_tool=1
  fi

  if command -v lsof >/dev/null 2>&1; then
    echo; echo "## lsof -nP -iTCP -sTCP:LISTEN"
    $S lsof -nP -iTCP -sTCP:LISTEN 2>&1
    has_tool=1
  fi

  if [ "$has_tool" -eq 0 ] && command -v netstat >/dev/null 2>&1; then
    echo "## netstat -tlpn"
    $S netstat -tlpn 2>&1
    has_tool=1
  fi

  if [ "$has_tool" -eq 0 ]; then
    echo "ss / lsof / netstat 명령어를 찾을 수 없습니다."
  fi

  echo; echo "## PID별 계정, 시작 시각, 명령줄"
  pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids=$($S lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $2}')
  fi
  if [ -z "$pids" ] && command -v ss >/dev/null 2>&1; then
    pids=$($S ss -ltnp 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2)
  fi

  if [ -n "$pids" ]; then
    echo "$pids" | tr ' ' '\n' | grep -v '^$' | sort -un | while read -r pid; do
      [ -n "$pid" ] && ps -o pid=,user=,lstart=,args= -p "$pid"
    done
  else
    echo "리슨 중인 프로세스 PID를 찾지 못했거나 포트를 점유한 프로세스가 없습니다."
  fi
}

case_process() {
  echo "## 전체 프로세스 (시작 시간순, 커널 스레드 제외)"
  ps -eo user,pid,lstart,args --sort=start_time | grep -v ' \['
  echo; echo "## 메모리 사용량 상위 (Top 20)"
  ps aux --sort=-%mem | head -n 21
  echo; echo "## CPU 사용량 상위 (Top 20)"
  ps aux --sort=-%cpu | head -n 21
}

case_installed() {
  echo "## /opt /srv /usr/local /home 디렉터리 목록"
  ls -lt /opt /srv /usr/local /home 2>&1

  echo; echo "## /etc/systemd/system/*.service 및 /etc/init.d (수동 등록 서비스)"
  ls -la /etc/systemd/system/*.service 2>/dev/null || echo "수동 systemd service 파일 없음"
  if [ -d /etc/init.d ]; then
    ls -la /etc/init.d 2>/dev/null
  fi

  echo; echo "## apt manual (수동 설치 패키지)"
  if command -v apt-mark >/dev/null 2>&1; then
    apt-mark showmanual 2>&1
  else
    echo "apt-mark 명령어 없음"
  fi

  if command -v snap >/dev/null 2>&1; then
    echo; echo "## snap list"
    snap list 2>&1
  fi

  echo; echo "## enabled services (활성화된 서비스)"
  if [ -d /run/systemd/system ]; then
    systemctl list-unit-files --type=service --state=enabled 2>&1 | grep -v -E 'ubuntu|systemd|snap'
  else
    echo "systemd 미사용 환경 (PID 1이 systemd가 아님)"
  fi
}

case_container() {
  found=0
  if command -v docker >/dev/null 2>&1; then
    echo "## docker ps -a"
    $S docker ps -a 2>&1
    found=1
  fi
  if command -v podman >/dev/null 2>&1; then
    echo; echo "## podman ps -a"
    $S podman ps -a 2>&1
    found=1
  fi
  if command -v crictl >/dev/null 2>&1; then
    echo; echo "## crictl ps -a"
    $S crictl ps -a 2>&1
    found=1
  fi
  if [ "$found" -eq 0 ]; then
    echo "컨테이너 런타임(docker / podman / crictl) 없음"
  fi
}

run cron      case_cron
run listen    case_listen
run process   case_process
run installed case_installed
run container case_container

# 한 파일로 압축 (내려받기용)
ARCHIVE="$H-solution.tar.gz"
( cd "$OUT" && tar -czf "$ARCHIVE" "$H"-*.txt )
FULL="$(cd "$OUT" && pwd)/$ARCHIVE"
echo
echo "archive: $FULL"
echo "내려받기 (내 PC에서): scp $(id -un)@$H:$FULL .    # 경유 서버가 있으면 scp -J <경유서버> ..."

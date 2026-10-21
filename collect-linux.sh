#!/bin/bash
# 솔루션 찾는 법 case별 명령 결과를 ${hostname}-${case}.txt 로 저장 (Ubuntu)
# 사용: bash collect-linux.sh [출력폴더]   (기본: 현재 폴더)

H=$(hostname)
OUT=${1:-.}
mkdir -p "$OUT"

S=""
[ "$(id -u)" -ne 0 ] && S="sudo"

run() {  # run <case명> <명령...>
  name=$1; shift
  f="$OUT/$H-$name.txt"
  { echo "# $H $name $(date '+%F %T')"; echo; "$@"; } > "$f" 2>&1
  echo "saved $f"
}

case_cron() {
  echo "## crontab (현재 계정)"; crontab -l 2>&1
  echo; echo "## 계정별 crontab 파일"; $S ls /var/spool/cron/crontabs 2>&1
  echo; echo "## /etc/crontab, /etc/cron.d"; grep -v -E '^\s*(#|$)' /etc/crontab /etc/cron.d/* 2>&1
  echo; echo "## systemd timers"; systemctl list-timers --all 2>&1
}

case_listen() {
  $S lsof -nP -iTCP -sTCP:LISTEN 2>&1
  echo; echo "## PID별 계정, 시작, 명령줄"
  $S lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $2}' | sort -un | while read -r pid; do
    ps -o pid=,user=,lstart=,args= -p "$pid"
  done
}

case_process() {
  ps -eo user,pid,lstart,args --sort=start_time | grep -v ' \['
}

case_installed() {
  echo "## /opt /srv /usr/local /home"; ls -lt /opt /srv /usr/local /home 2>&1
  echo; echo "## apt manual"; apt-mark showmanual 2>&1
  echo; echo "## enabled services"; systemctl list-unit-files --type=service --state=enabled 2>&1 | grep -v -E 'ubuntu|systemd|snap'
}

case_container() {
  if command -v docker >/dev/null 2>&1; then
    $S docker ps -a 2>&1
  else
    echo "docker 없음"
  fi
}

run cron      case_cron
run listen    case_listen
run process   case_process
run installed case_installed
run container case_container

# 한 파일로 압축 (내려받기용)
ARCHIVE="$H-solution.tar.gz"
( cd "$OUT" && tar -czf "$ARCHIVE" "$H"-cron.txt "$H"-listen.txt "$H"-process.txt "$H"-installed.txt "$H"-container.txt )
FULL="$(cd "$OUT" && pwd)/$ARCHIVE"
echo
echo "archive: $FULL"
echo "내려받기 (내 PC에서): scp $(id -un)@$H:$FULL .    # 경유 서버가 있으면 scp -J <경유서버> ..."

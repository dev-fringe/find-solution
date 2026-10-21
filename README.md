# 서버에서 솔루션(상용 프로세스) 찾는 법

처음 보는 서버에 들어갔을 때, 어떤 솔루션이 돌고 있는지 찾는 순서. macOS/Linux 공용 (표기 없으면 공용).

## 1. 열린 포트 (가장 확실한 단서)

```
lsof -nP -iTCP -sTCP:LISTEN
ss -ltnp                       # Linux (root면 프로세스명까지)
```

서비스는 대부분 포트를 연다. 포트 번호와 프로세스명을 같이 보면 솔루션이 거의 나온다.

## 2. OS 기본이 아닌 프로세스

```
ps -ef | grep -v -E '\[|/usr/(sbin|lib)|/System|/sbin/'
ps aux --sort=-%mem | head -20     # Linux: 메모리 많이 쓰는 순
```

후보 기준:
- 경로: `/opt`, `/home`, `/Applications`, `/srv`, `/usr/local` 아래
- 이름: `java`, `node`, `python`, `tomcat`, `nginx` 등

## 3. 자동 시작으로 등록된 것

```
systemctl list-units --type=service --state=running    # Linux
launchctl list | grep -v com.apple                     # macOS
crontab -l ; ls /etc/cron.d
```

재부팅 때 자동으로 뜨는 상용 서비스는 대개 여기에 등록돼 있다.

## 4. 설치 위치

```
ls /opt /srv /usr/local /Applications
docker ps                      # 컨테이너로 돌리는 경우
```

## 5. 후보를 찾은 뒤

```
ps -ef | grep -E '이름'
ls -l /proc/<PID>/cwd          # Linux: 실행 위치
lsof -p <PID> | head           # 열린 파일, 로그 위치
```

이름이 정해지면 같은 이름으로 다른 서버들도 확인한다.

## 요약

포트(1) → PID 확인 → 경로/로그 추적(5). 포트가 없는 배치성 프로세스는 2, 3번으로 찾는다.

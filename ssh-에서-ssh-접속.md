# ssh에서 ssh로 들어가는 법 (서버 경유 접속)

A(내 PC) → B(경유 서버, 점프/배스천) → C(목적 서버) 구조를 가정한다.

## 1. 가장 간단: -J (ProxyJump)

```
ssh -J userB@B userC@C
ssh -J userB@B:22 -p 2222 userC@C             # 포트가 다를 때
ssh -J userB1@B1,userB2@B2 userC@C            # 경유 서버가 둘 이상
```

B에 한 번 로그인했다가 다시 `ssh`하는 것과 결과는 같지만, 내 PC에서 한 줄로 끝난다.
키는 **내 PC의 키**로 B와 C 모두 인증한다(B에 개인키를 둘 필요 없음).

## 2. 자주 쓰면 ~/.ssh/config에 등록

```
Host bastion
    HostName 10.0.0.10
    User ubuntu
    IdentityFile ~/.ssh/key.pem

Host app-prd1
    HostName 10.0.1.25
    User appuser
    ProxyJump bastion
    IdentityFile ~/.ssh/key.pem
```

이후에는 `ssh app-prd1` 한 줄로 접속한다. (Windows: `C:\Users\<계정>\.ssh\config`)

## 3. B에 이미 로그인한 상태에서 C로 들어가기

```
ssh userC@C
```

이때 인증 방법은 둘 중 하나다.

- **B에 키가 있는 경우**: `ssh -i ~/.ssh/key.pem userC@C`
- **내 PC 키를 그대로 쓰고 싶은 경우**: 처음 접속할 때 에이전트 전달(`-A`)을 켠다.

```
ssh -A userB@B            # 내 PC에서 B로 (에이전트 전달)
ssh userC@C               # B에서 C로 (내 PC 키로 인증)
```

`-A`는 B의 관리자(root)가 내 에이전트를 가로쓸 수 있다. 신뢰하지 않는 서버에는 쓰지 말고, 가능하면 1번 `-J`를 쓴다.

## 4. 명령만 실행하고 나오기 (접속 없이)

```
ssh -J userB@B userC@C 'hostname; uptime'
ssh -J userB@B -t userC@C 'sudo lsof -nP -iTCP -sTCP:LISTEN'     # sudo가 필요하면 -t
```

가이드의 명령을 여러 서버에서 한 번에 돌릴 때 쓴다.

```
for h in app-prd1 app-prd2 app-prd3; do echo "== $h"; ssh -t $h 'sudo lsof -nP -iTCP -sTCP:LISTEN'; done
```

## 5. 파일 주고받기 (경유 서버 통과)

```
scp -J userB@B userC@C:/opt/app/app.log .
scp -J userB@B ./script.sh userC@C:/tmp/
```

## 6. 포트 터널 (경유 서버를 통해 C의 포트에 접근)

```
ssh -J userB@B -L 8080:localhost:8080 userC@C
```

접속을 유지한 채 내 PC 브라우저에서 `http://localhost:8080`으로 C의 서비스를 본다.

## 7. AWS EC2인 경우

키 파일(.pem)로 직접 접속하거나, 포트 22를 열지 않는 방법이 있다.

```
ssh -i key.pem ubuntu@<퍼블릭IP>                      # 일반 접속
aws ssm start-session --target <인스턴스ID>             # SSM Session Manager (22번 포트 불필요)
```

- Ubuntu AMI 기본 계정은 `ubuntu`. Amazon Linux는 `ec2-user`.
- SSM은 인스턴스에 SSM Agent와 IAM 역할이 있어야 한다.
- 프라이빗 서브넷의 서버는 퍼블릭 IP가 없으므로 1번 `-J`로 배스천을 거치거나 SSM을 쓴다.

## 8. 접속이 안 될 때

```
ssh -v -J userB@B userC@C          # -vv, -vvv로 자세히
ssh-add -l                         # 에이전트에 키가 올라와 있는지 (-A 사용 시)
chmod 600 ~/.ssh/key.pem           # 키 권한 (Windows는 파일 속성의 보안에서 본인만)
```

- `Permission denied (publickey)`: 키 파일, 계정 이름, 서버의 `authorized_keys` 확인
- `Connection timed out`: 보안그룹, 방화벽, 포트 확인
- `Host key verification failed`: `~/.ssh/known_hosts`에서 해당 줄 삭제 (서버를 새로 만들었을 때)

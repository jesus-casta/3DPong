#!/bin/bash
set -euo pipefail
cd /workspace/3DPong
export ANDROID_HOME=/workspace/android-sdk ANDROID_USER_HOME=/workspace/.android GRADLE_USER_HOME=/workspace/.gradle
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
if ! compgen -G '/workspace/jdk/jdk-*/bin/javac' >/dev/null; then
 curl --fail --location --silent --show-error https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz -o "$work_dir/jdk.tar.gz"
 curl --fail --location --silent --show-error https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz.sha256 -o "$work_dir/jdk.sha256"
 python - "$work_dir" <<'PY'
import sys,hashlib,tarfile,pathlib
p=pathlib.Path(sys.argv[1]);assert hashlib.sha256((p/'jdk.tar.gz').read_bytes()).hexdigest()==(p/'jdk.sha256').read_text().split()[0]
pathlib.Path('/workspace/jdk').mkdir(exist_ok=True)
with tarfile.open(p/'jdk.tar.gz') as archive:archive.extractall('/workspace/jdk',filter='data')
PY
fi
export JAVA_HOME
JAVA_HOME=$(find /workspace/jdk -mindepth 1 -maxdepth 1 -type d -name 'jdk-*' | sort -V | tail -n 1)
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
 curl --fail --location --silent --show-error https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -o "$work_dir/android.zip"
 python - "$work_dir/android.zip" <<'PY'
import sys,hashlib,zipfile,pathlib
p=pathlib.Path(sys.argv[1]);assert hashlib.sha1(p.read_bytes()).hexdigest()=='e025545c62a8e64c7559119566a569fb1dec5f60'
target=pathlib.Path('/workspace/android-sdk/cmdline-tools');target.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(p) as archive:archive.extractall(target)
(target/'cmdline-tools').rename(target/'latest')
PY
 chmod +x "$ANDROID_HOME"/cmdline-tools/latest/bin/*
fi
if [ ! -d "$ANDROID_HOME/platforms/android-36" ] || [ ! -d "$ANDROID_HOME/build-tools/35.0.0" ]; then
 "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" 'platforms;android-36' 'build-tools;35.0.0' 'platform-tools' <<'LICENSE'
y
y
y
y
y
y
y
y
LICENSE
fi
# JVM clients need the platform proxy and existing trusted CA store.
python - <<'PY'
import os,urllib.parse,pathlib
value=os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy')
if value:
 p=urllib.parse.urlsplit(value)
 if p.username or p.password:raise SystemExit('An authenticated proxy needs a supported JVM binding; do not save credentials.')
 target=pathlib.Path('/workspace/.gradle/gradle.properties');target.parent.mkdir(exist_ok=True)
 props={'systemProp.https.proxyHost':p.hostname,'systemProp.https.proxyPort':str(p.port or 80),'systemProp.http.proxyHost':p.hostname,'systemProp.http.proxyPort':str(p.port or 80)}
 if pathlib.Path('/etc/ssl/certs/java/cacerts').exists():props['systemProp.javax.net.ssl.trustStore']='/etc/ssl/certs/java/cacerts'
 existing=target.read_text().splitlines() if target.exists() else []
 existing=[s for s in existing if s.split('=',1)[0] not in props]
 target.write_text('\n'.join(existing+[k+'='+v for k,v in props.items()])+'\n')
PY
npm ci --cache /workspace/.npm-cache --no-audit --no-fund
npm test
./scripts/check-native-physics.sh
./android/gradlew -p android assembleDebug --max-workers=2 --console=plain

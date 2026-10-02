#!/usr/bin/env python3
"""Generate a private local Android signing key once, without printing secrets."""
import os
from pathlib import Path
import secrets
import subprocess
import shutil

project = Path(__file__).resolve().parents[1]
signing_dir = Path.home() / '.local/share/zvuk-personal/signing'
signing_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
keystore = signing_dir / 'personal.jks'
password_file = signing_dir / 'password'
properties = project / 'android/key.properties'
if keystore.exists() != password_file.exists():
    raise SystemExit('Signing material is incomplete; restore the existing key/password backup.')
if not keystore.exists():
    password = secrets.token_urlsafe(36)
    env = dict(os.environ, ZVUK_SIGNING_PASSWORD=password)
    java_home = os.environ.get('JAVA_HOME')
    keytool = str(Path(java_home) / 'bin/keytool') if java_home else shutil.which('keytool')
    if not keytool:
        raise SystemExit('Install JDK 17+ and set JAVA_HOME before creating the signing key.')
    subprocess.run([keytool, '-genkeypair', '-keystore', str(keystore), '-alias', 'personal', '-storetype', 'JKS', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000', '-storepass:env', 'ZVUK_SIGNING_PASSWORD', '-keypass:env', 'ZVUK_SIGNING_PASSWORD', '-dname', 'CN=Zvuk Personal, OU=Personal, O=Personal, C=RU'], env=env, check=True, capture_output=True)
    password_file.write_text(password)
    password_file.chmod(0o600)
    keystore.chmod(0o600)
password = password_file.read_text()
properties.write_text(f'storeFile={keystore}\nstorePassword={password}\nkeyAlias=personal\nkeyPassword={password}\n')
properties.chmod(0o600)
print('Personal signing key is ready; credentials stay outside version control.')

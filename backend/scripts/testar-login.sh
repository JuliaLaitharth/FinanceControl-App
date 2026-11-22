#!/bin/bash
# Verifica se um e-mail/senha existem em um backend (sem expor a senha).
# Uso:  bash scripts/testar-login.sh https://SUA-URL
# Atenção: cada tentativa errada conta para o bloqueio (5 falhas = 15 minutos).
BASE="${1:?Uso: bash scripts/testar-login.sh https://SUA-URL}"
read -rp "E-mail: " EMAIL
read -rsp "Senha (não aparece na tela): " SENHA
echo
export EMAIL SENHA
python3 - "$BASE" <<'PY'
import json, os, sys, urllib.request, urllib.error
base = sys.argv[1].rstrip("/")
req = urllib.request.Request(base + "/auth/login",
    data=json.dumps({"email": os.environ["EMAIL"], "senha": os.environ["SENHA"]}).encode(),
    headers={"Content-Type": "application/json"})
print("Backend testado:", base)
try:
    r = urllib.request.urlopen(req)
    print("HTTP", r.status, "-> o usuário EXISTE neste backend e a senha confere")
except urllib.error.HTTPError as e:
    dica = {401: "-> e-mail ou senha incorretos NESTE backend (o usuário não existe aqui, ou a senha é outra)",
            429: "-> conta bloqueada por tentativas: aguarde 15 minutos"}.get(e.code, "")
    print("HTTP", e.code, dica)
PY

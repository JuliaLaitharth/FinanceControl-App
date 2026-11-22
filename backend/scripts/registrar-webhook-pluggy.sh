#!/bin/bash
# Registra o webhook do Pluggy apontando para o backend publicado.
#
# Uso:   bash scripts/registrar-webhook-pluggy.sh https://SUA-URL
#
# - Credenciais do Pluggy: lidas de backend/.env (PLUGGY_CLIENT_ID / PLUGGY_CLIENT_SECRET)
# - Segredo do webhook: pedido num campo oculto (é o PLUGGY_WEBHOOK_SECRET do backend publicado)
# - Remove webhooks antigos (túneis temporários e a mesma URL) e cadastra os novos.
set -u
BASE="${1:-}"
if [ -z "$BASE" ]; then echo "Informe a URL do backend: bash $0 https://SUA-URL"; exit 1; fi
BASE="${BASE%/}"
URL="$BASE/webhooks/pluggy"

cd "$(dirname "$0")/.." || exit 1
set -a; . ./.env; set +a
: "${PLUGGY_CLIENT_ID:?PLUGGY_CLIENT_ID ausente no .env}"
: "${PLUGGY_CLIENT_SECRET:?PLUGGY_CLIENT_SECRET ausente no .env}"

read -rs -p "Cole o PLUGGY_WEBHOOK_SECRET do backend publicado e tecle Enter (não aparece na tela): " SEGREDO
echo
SEGREDO="$(printf '%s' "$SEGREDO" | tr -d '[:space:]')"
if [ "${#SEGREDO}" -ne 64 ]; then
  echo "O segredo tem ${#SEGREDO} caracteres; o esperado são 64. Copie o valor direto da variável no Railway e tente de novo."
  exit 1
fi

API_KEY=$(python3 - <<PY
import json, os, urllib.request
req = urllib.request.Request("https://api.pluggy.ai/auth",
    data=json.dumps({"clientId": os.environ["PLUGGY_CLIENT_ID"], "clientSecret": os.environ["PLUGGY_CLIENT_SECRET"]}).encode(),
    headers={"Content-Type": "application/json"})
print(json.load(urllib.request.urlopen(req))["apiKey"])
PY
)
[ -n "$API_KEY" ] || { echo "Falha ao autenticar no Pluggy"; exit 1; }
export API_KEY URL SEGREDO

python3 - <<'PY'
import json, os, urllib.request, urllib.error

def chamar(metodo, caminho, corpo=None):
    req = urllib.request.Request("https://api.pluggy.ai" + caminho, method=metodo,
        data=None if corpo is None else json.dumps(corpo).encode(),
        headers={"X-API-KEY": os.environ["API_KEY"], "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            texto = r.read().decode()
            return r.status, (json.loads(texto) if texto else {})
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        try: return e.code, json.loads(texto)
        except Exception: return e.code, {"message": texto[:200]}

url = os.environ["URL"]
_, lista = chamar("GET", "/webhooks")
itens = lista.get("results", []) if isinstance(lista, dict) else lista
print("== removendo webhooks antigos ==")
removidos = 0
for w in itens:
    if "trycloudflare" in w.get("url", "") or w.get("url") == url:
        status, _ = chamar("DELETE", "/webhooks/" + w["id"])
        print(f"  apagado {w.get('event')} {w.get('url')}: HTTP {status}")
        removidos += 1
if not removidos: print("  (nenhum)")

print("== cadastrando ==")
for evento in ("item/updated", "item/created"):
    status, resp = chamar("POST", "/webhooks", {"event": evento, "url": url, "headers": {"x-webhook-secret": os.environ["SEGREDO"]}})
    print(f"  {evento}: " + ("ok" if resp.get("id") else f"ERRO {status}: {resp.get('message')}"))
PY

echo "== teste de autenticação no backend publicado =="
c1=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL" -H 'Content-Type: application/json' -H "x-webhook-secret: $SEGREDO" -d '{"event":"item/updated","itemId":"teste"}')
c2=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$URL" -H 'Content-Type: application/json' -H "x-webhook-secret: errado" -d '{"event":"item/updated","itemId":"teste"}')
echo "  segredo correto: HTTP $c1 (esperado 200)"
echo "  segredo errado:  HTTP $c2 (esperado 401)"
[ "$c1" = "200" ] && [ "$c2" = "401" ] && echo "Tudo certo." || echo "ATENÇÃO: confira o segredo (precisa ser o mesmo do Railway)."

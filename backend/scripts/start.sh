#!/bin/sh
# Sobe a API: aplica as migrations e inicia o servidor.
#
# Em plataformas como o Railway, o banco pode ainda estar iniciando (ou o DNS da rede
# privada ainda não resolver) quando o container nasce. Em vez de morrer na primeira
# falha, tenta de novo por um tempo; esgotadas as tentativas, sai com erro para a
# plataforma registrar a falha.
MAX="${MIGRATE_MAX_TENTATIVAS:-24}"
ESPERA="${MIGRATE_ESPERA_SEGUNDOS:-5}"

tentativa=1
until npx prisma migrate deploy; do
  if [ "$tentativa" -ge "$MAX" ]; then
    echo "[start] migrations não puderam ser aplicadas após $MAX tentativas. Encerrando."
    exit 1
  fi
  echo "[start] banco indisponível ou migration falhou (tentativa $tentativa/$MAX). Nova tentativa em ${ESPERA}s..."
  tentativa=$((tentativa + 1))
  sleep "$ESPERA"
done

echo "[start] migrations aplicadas. Iniciando o servidor."
exec node dist/main

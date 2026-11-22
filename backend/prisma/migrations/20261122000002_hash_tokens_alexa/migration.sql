-- Tokens da Alexa passam a ser guardados só como SHA-256 (hex, 64 caracteres), como na tabela
-- de sessões. Os tokens já emitidos continuam valendo: o app recebe o valor original e o
-- backend compara pelo hash. A condição torna a migration segura de repetir.
UPDATE "vinculo_alexa"
SET "access_token"  = encode(sha256(convert_to("access_token",  'UTF8')), 'hex'),
    "refresh_token" = encode(sha256(convert_to("refresh_token", 'UTF8')), 'hex')
WHERE length("refresh_token") <> 64;

-- Alerta de saldo mínimo passa a ser por conta (DVP UC04); regras antigas ficam com conta_id nulo
ALTER TABLE "regra_alerta" ADD COLUMN "conta_id" INTEGER;

CREATE INDEX "regra_alerta_usuario_id_conta_id_idx" ON "regra_alerta"("usuario_id", "conta_id");

ALTER TABLE "regra_alerta"
  ADD CONSTRAINT "regra_alerta_conta_id_fkey"
  FOREIGN KEY ("conta_id") REFERENCES "conta_bancaria"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

import { Type } from 'class-transformer';
import { IsIn, IsInt, IsNumber, IsOptional, Min } from 'class-validator';

export const TIPOS_EVENTO = ['SALDO_MINIMO', 'TRANSACAO_GRANDE', 'DESPESA_CATEGORIA', 'PIX_RECEBIDO', 'PIX_ENVIADO'] as const;
/** PUSH = notificação no app; ALEXA = alerta proativo; AMBOS = os dois. */
export const CANAIS = ['PUSH', 'ALEXA', 'AMBOS'] as const;

export class CreateRegraAlertaDto {
  @IsIn(TIPOS_EVENTO)
  tipoEvento!: string;

  @IsOptional()
  @IsIn(['MENOR_QUE', 'MAIOR_QUE'])
  operador?: string;

  /** Obrigatório e > 0, exceto nos alertas de Pix (opcional: avisa só acima do valor). */
  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  valorLimite?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  categoriaId?: number;

  /** Obrigatório para SALDO_MINIMO: um alerta por conta. */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  contaId?: number;

  @IsIn(CANAIS)
  canal!: string;
}

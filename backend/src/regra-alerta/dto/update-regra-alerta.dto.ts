import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsNumber, IsOptional, Min } from 'class-validator';
import { CANAIS, TIPOS_EVENTO } from './create-regra-alerta.dto.js';

/**
 * Todos os campos são opcionais: o app envia só `ativa` ao ligar/desligar uma
 * regra. O serviço valida o resultado final (regra existente + alterações).
 */
export class UpdateRegraAlertaDto {
  @IsOptional()
  @IsIn(TIPOS_EVENTO)
  tipoEvento?: string;

  @IsOptional()
  @IsIn(['MENOR_QUE', 'MAIOR_QUE'])
  operador?: string;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  valorLimite?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  categoriaId?: number;

  @IsOptional()
  @IsIn(CANAIS)
  canal?: string;

  @IsOptional()
  @IsBoolean()
  ativa?: boolean;
}

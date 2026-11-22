import { Body, Controller, Delete, Get, HttpCode, Ip, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { LgpdService } from '../lgpd/lgpd.service';
import { Transform } from 'class-transformer';
import { IsEmail, IsString, MaxLength, MinLength } from 'class-validator';
import { AuthService } from './auth.service';
import { BiometriaDto } from './dto/biometria.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { RegisterDto } from './dto/register.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

class FcmTokenDto {
  @IsString()
  token!: string;
}

class AlexaIdDto {
  @IsString()
  alexaUserId!: string;
}

class AtualizarPerfilDto {
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  nome!: string;
}

class AlterarSenhaDto {
  @IsString()
  senhaAtual!: string;

  @IsString()
  @MinLength(8)
  novaSenha!: string;
}

class AlterarEmailDto {
  @IsString()
  senhaAtual!: string;

  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  @IsEmail({}, { message: 'E-mail inválido' })
  novoEmail!: string;
}

interface AuthRequest {
  user: { userId: number; sessaoId: string };
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly lgpd: LgpdService,
  ) {}

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('register')
  register(@Body() dto: RegisterDto, @Ip() ip: string) {
    return this.auth.register(dto, ip);
  }

  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('login')
  @HttpCode(200)
  login(@Body() dto: LoginDto, @Ip() ip: string) {
    return this.auth.login(dto, ip);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto);
  }

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('forgot-password')
  @HttpCode(200)
  forgotPassword(@Body() dto: ForgotPasswordDto, @Ip() ip: string) {
    return this.auth.forgotPassword(dto, ip);
  }

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('reset-password')
  @HttpCode(200)
  resetPassword(@Body() dto: ResetPasswordDto, @Ip() ip: string) {
    return this.auth.resetPassword(dto, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Post('logout')
  @HttpCode(204)
  async logout(@Req() req: AuthRequest, @Ip() ip: string) {
    await this.auth.logout(req.user.userId, req.user.sessaoId, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('biometria')
  biometria(@Req() req: AuthRequest, @Body() dto: BiometriaDto, @Ip() ip: string) {
    return this.auth.alterarBiometria(req.user.userId, dto.ativa, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Get('me')
  me(@Req() req: AuthRequest) {
    return this.auth.me(req.user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('fcm-token')
  @HttpCode(204)
  registrarFcmToken(@Req() req: AuthRequest, @Body() dto: FcmTokenDto) {
    return this.auth.registrarFcmToken(req.user.userId, dto.token);
  }

  @UseGuards(JwtAuthGuard)
  @Get('alexa')
  statusAlexa(@Req() req: AuthRequest) {
    return this.auth.statusAlexa(req.user.userId);
  }

  @UseGuards(JwtAuthGuard)
  @Delete('alexa')
  @HttpCode(204)
  async desvincularAlexa(@Req() req: AuthRequest, @Ip() ip: string) {
    await this.auth.desvincularAlexa(req.user.userId, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('alexa-id')
  @HttpCode(204)
  async vincularAlexaId(@Req() req: AuthRequest, @Body() dto: AlexaIdDto) {
    await this.auth.vincularAlexaId(req.user.userId, dto.alexaUserId);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('perfil')
  atualizarPerfil(@Req() req: AuthRequest, @Body() dto: AtualizarPerfilDto) {
    return this.auth.atualizarPerfil(req.user.userId, dto.nome);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('email')
  @HttpCode(200)
  alterarEmail(@Req() req: AuthRequest, @Body() dto: AlterarEmailDto, @Ip() ip: string) {
    return this.auth.alterarEmail(req.user.userId, dto.senhaAtual, dto.novoEmail, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Patch('senha')
  @HttpCode(200)
  alterarSenha(@Req() req: AuthRequest, @Body() dto: AlterarSenhaDto, @Ip() ip: string) {
    return this.auth.alterarSenha(req.user.userId, dto.senhaAtual, dto.novaSenha, ip);
  }

  @UseGuards(JwtAuthGuard)
  @Delete('conta')
  @HttpCode(204)
  async excluirConta(@Req() req: AuthRequest, @Ip() ip: string) {
    await this.lgpd.excluirConta(req.user.userId, ip);
  }
}
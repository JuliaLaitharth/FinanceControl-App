import { PrismaClient } from '@prisma/client';
import { CATEGORIAS_PADRAO } from '../src/categoria/categorias-padrao';

const prisma = new PrismaClient();

const categoriasPadrao = CATEGORIAS_PADRAO;

async function main() {
  console.log('Seed: criando categorias padrão do sistema...');

  for (const cat of categoriasPadrao) {
    await prisma.categoria.upsert({
      where: {
        // Upsert por nome + padraoSistema via campo calculado não é direto no Prisma,
        // então usamos findFirst + create/update manual
        id: (
          await prisma.categoria.findFirst({
            where: { nome: cat.nome, padraoSistema: true, usuarioId: null },
          })
        )?.id ?? -1,
      },
      update: { icone: cat.icone, tipo: cat.tipo },
      create: {
        nome: cat.nome,
        tipo: cat.tipo,
        icone: cat.icone,
        padraoSistema: true,
        usuarioId: null,
      },
    });
  }

  console.log(`Seed concluído: ${categoriasPadrao.length} categorias criadas/atualizadas.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

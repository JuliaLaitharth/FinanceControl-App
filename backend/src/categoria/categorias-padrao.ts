/** Categorias do sistema. Usadas no seed e garantidas na subida do backend. */
export const CATEGORIAS_PADRAO = [
  { nome: 'Alimentação', tipo: 'DESPESA', icone: '🍽️' },
  { nome: 'Transporte', tipo: 'DESPESA', icone: '🚌' },
  { nome: 'Moradia', tipo: 'DESPESA', icone: '🏠' },
  { nome: 'Saúde', tipo: 'DESPESA', icone: '💊' },
  { nome: 'Educação', tipo: 'DESPESA', icone: '📚' },
  { nome: 'Lazer', tipo: 'DESPESA', icone: '🎮' },
  { nome: 'Vestuário', tipo: 'DESPESA', icone: '👕' },
  { nome: 'Serviços', tipo: 'DESPESA', icone: '📱' },
  { nome: 'Pix enviado', tipo: 'DESPESA', icone: '📤' },
  { nome: 'Pix recebido', tipo: 'RECEITA', icone: '📥' },
  { nome: 'Transferência', tipo: 'DESPESA', icone: '↔️' },
  { nome: 'Renda', tipo: 'RECEITA', icone: '💰' },
  { nome: 'Investimentos', tipo: 'RECEITA', icone: '📈' },
  { nome: 'Outros', tipo: 'DESPESA', icone: '📦' },
] as const;

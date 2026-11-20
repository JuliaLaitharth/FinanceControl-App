// Gera lambda.zip: o código compilado + só as dependências de produção.
// Uso: npm run package   →   envie lambda.zip na AWS Lambda (handler: dist/index.handler).
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const raiz = path.join(__dirname, '..');
const saida = path.join(raiz, 'lambda-build');
const zip = path.join(raiz, 'lambda.zip');

const rodar = (cmd, cwd) => execSync(cmd, { cwd, stdio: 'inherit' });

fs.rmSync(saida, { recursive: true, force: true });
fs.rmSync(zip, { force: true });

rodar('npm run build', raiz);

fs.mkdirSync(saida);
fs.cpSync(path.join(raiz, 'dist'), path.join(saida, 'dist'), { recursive: true });
for (const f of ['package.json', 'package-lock.json']) {
  if (fs.existsSync(path.join(raiz, f))) fs.copyFileSync(path.join(raiz, f), path.join(saida, f));
}

rodar('npm install --omit=dev --no-audit --no-fund', saida);
rodar(`zip -qr "${zip}" .`, saida);

const mb = (fs.statSync(zip).size / 1024 / 1024).toFixed(1);
console.log(`\nlambda.zip gerado (${mb} MB). Handler na Lambda: dist/index.handler`);

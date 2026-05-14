export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
#netlify deploy --prod --site your_site_id
netlify deploy --prod --site 7733b4c2-ca9d-4131-af46-71c873ea9a4e

git add .
git commit -m 'fixes'
git push
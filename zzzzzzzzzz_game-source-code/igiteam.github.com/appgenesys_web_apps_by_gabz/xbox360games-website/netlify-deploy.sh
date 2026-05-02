export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
#netlify deploy --prod --site your_site_id
netlify deploy --prod --site 6a6d02d3-7cbd-43c6-8fda-da934eb71195

git add .
git commit -m 'fixes'
git push
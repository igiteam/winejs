export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
#netlify deploy --prod --site your_site_id
netlify deploy --prod --site a8fa99c6-1765-4326-a357-bd7a402f7e21

# git add .
# git commit -m 'fixes'
# git push
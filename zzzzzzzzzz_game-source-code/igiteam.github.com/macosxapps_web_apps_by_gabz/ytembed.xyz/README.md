NETLIFY REACT APP
i setup a react app, i uploaded from this link i can view
 https://ytembedxyz.netlify.app/

# Install Netlify CLI globally

npm install -g netlify-cli

# Login to Netlify

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
netlify login

Already logged in via netlify config on your machine

Run `netlify status` for account details

or run `netlify switch` to switch accounts

To see all available commands run: netlify help

# Initialize and deploy

cd your-website-folder
netlify init

# Follow prompts to create new site or connect existing

netlify logout

# Deploy to production

netlify deploy --prod

#netlify deploy
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export NODE_OPTIONS=--openssl-legacy-provider
node -v
npm -v
netlify deploy --prod

Initial State

- The system showed 248 npm packages looking for funding (can view with npm fund) 
  Commands and Events:

1. First Netlify Deploy Attempt 
   netlify deploy

- CLI attempted to log into Netlify account
- Opened Safari to https://app.netlify.com/authorize?response_type=ticket&ticket=1b8093b4a334c1643bace36afe654e4e
- User had to login through browser
- Console got stuck on "authentication in progress"
- User pressed Ctrl+C to cancel 
  Second Netlify Deploy Attempt

netlify deploy

- Opened new auth URL: https://app.netlify.com/authorize?response_type=ticket&ticket=c5e66cc6e0d776724b22a3d2dc5898a5
- Since user was already logged in, had to accept authentication for React upload permissions
- Authentication successful: "You are now logged into your Netlify account!"
- CLI crashed with error when trying to select team:
- Error: Netlify CLI has terminated unexpectedly
- TypeError: Cannot read properties of undefined (reading 'value')
- Error suggested possible CLI version issue 
  Third Netlify Deploy Attempt (Successful)

netlify deploy

- Created new site:
  - Team: IGIRemakeTeam
  - Site name: ytembed
  - Admin URL: https://app.netlify.com/projects/ytembed
  - Live URL: https://ytembed.netlify.app
  - Site ID: 398ef3a2-276c-409c-9674-51fe1a4af309
- Build process:
  - Ran npm run build (React build)
  - Showed ESLint warnings in App.js
  - Successful build with production-ready files
- Deployed draft version: \* Draft URL: https://682a2ffbe227ee75ddb6d0fa--ytembed.netlify.app 
  Production Deploy

1. netlify deploy --prod 
   _ Ran build again (same warnings) 
   _ Deployed to production:
   _ Production URL: https://ytembed.netlify.app 
   _ Unique deploy URL: https://682a304d16d26dd1515e24ed--ytembed.netlify.app 
   System Information:

- OS: macOS 11.7.10
- CPU: Intel Core i7-4870HQ
- Node: v22.15.1
- npm: 10.9.2
- Netlify CLI: 21.4.2
- Browsers: Chrome 136, Safari 16.6 
  Authentication Flow:

1. First attempt required full login in Safari
2. Got stuck in console after browser login
3. Second attempt (after Ctrl+C) required just authorization approval
4. After approval, deployment process could continue 
   The entire process resulted in a successfully deployed React application to Netlify, first as a draft version and then to production.

I bought a domain on Namecheap
ytembed.xyz
After I uploaded web to project>domain>add new domain> got the dns records
dns1.p05.nsone.net
dns2.p05.nsone.net
dns3.p05.nsone.net
dns4.p05.nsone.net
-> added this in nemacheap > domain > NAMESERVERS -> CUSTOM NAMESERVER

Back on netlify
Domain Management

> wait until domain is found

CREATE SSL

DONE

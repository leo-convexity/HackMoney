FROM node:14-slim

USER node

RUN mkdir -p /home/node/app

WORKDIR /home/node/app

COPY --chown=node package.json ./
COPY --chown=node yarn.lock ./

RUN yarn install

COPY . .

EXPOSE 8080
CMD ["yarn", "start"]

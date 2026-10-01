FROM node:22.9-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /src/dist /usr/share/nginx/html
USER nginx
HEALTHCHECK --interval=30s CMD wget -qO- http://localhost:8080/ || exit 1
EXPOSE 8080

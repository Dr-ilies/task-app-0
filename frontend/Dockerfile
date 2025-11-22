# Étape 1: Base Nginx
FROM nginx:1.23-alpine

# Copier notre configuration Nginx personnalisée
# Elle remplace la configuration par défaut
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copier les fichiers statiques de notre application
COPY index.html /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/

# Exposer le port 80 (standard pour Nginx)
EXPOSE 80
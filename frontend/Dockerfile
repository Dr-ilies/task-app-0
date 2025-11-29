# Étape 1: Base Nginx
FROM nginx:1.23-alpine

# Copier le template de configuration Nginx
COPY nginx.conf.template /etc/nginx/templates/default.conf.template

# Copier les fichiers statiques de notre application
COPY index.html /usr/share/nginx/html/
COPY app.js /usr/share/nginx/html/

# Exposer le port 80
EXPOSE 80

# La variable d'environnement NGINX_ENVSUBST_OUTPUT_DIR est utilisée par l'image nginx officielle
# pour savoir où placer le fichier de conf généré. Par défaut /etc/nginx/conf.d/
# Les variables à substituer doivent être définies dans l'environnement du conteneur.
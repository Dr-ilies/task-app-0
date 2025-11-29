#!/bin/sh

# Remplacer les variables dans le template et créer le fichier de conf final
# On liste explicitement les variables à remplacer pour éviter de casser d'autres syntaxes nginx ($uri, etc.)
envsubst '${AUTH_API_URL} ${TASKS_API_URL}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

# Démarrer Nginx en premier plan
exec nginx -g 'daemon off;'

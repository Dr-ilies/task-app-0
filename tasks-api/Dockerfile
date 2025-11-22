# Étape 1: Base Python
FROM python:3.10-slim

# Définir le répertoire de travail
WORKDIR /app

# Créer un utilisateur non-root pour la sécurité
RUN useradd -m -s /bin/bash appuser

# Copier les dépendances (en tant que root, mais définir le propriétaire)
COPY --chown=appuser:appuser requirements.txt .

# Copier le code de l'application (en tant que root, mais définir le propriétaire)
COPY --chown=appuser:appuser . .

# Donner la propriété du répertoire de travail à appuser
RUN chown -R appuser:appuser /app

# Passer à l'utilisateur non-root
USER appuser

# Installer les dépendances en tant que 'appuser'
# RUN pip install --no-cache-dir --user -r requirements.txt
RUN pip install --user -r requirements.txt

# Exposer le port
EXPOSE 8000

# Lancer l'application
CMD ["/home/appuser/.local/bin/uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
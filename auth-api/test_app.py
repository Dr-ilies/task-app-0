import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app import app, get_db, Base

# --- Configuration de la base de données de test ---
# Utilisation de SQLite en mémoire pour les tests
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# --- Fixtures Pytest ---

@pytest.fixture(scope="session", autouse=True)
def create_test_database():
    """Crée la base de données de test une fois par session."""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

@pytest.fixture(scope="function")
def db_session():
    """Crée une nouvelle session de base de données pour chaque test."""
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)
    
    yield session
    
    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture(scope="function")
def test_client(db_session):
    """Crée un client de test FastAPI qui utilise la session de test."""
    
    # Remplacer la dépendance get_db par notre session de test
    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    
    client = TestClient(app)
    yield client
    
    # Nettoyer les remplacements après le test
    app.dependency_overrides = {}

# --- Tests ---

def test_register_user(test_client):
    """Teste l'inscription d'un nouvel utilisateur."""
    response = test_client.post("/register", json={"username": "newuser", "password": "password123"})
    assert response.status_code == 201
    data = response.json()
    assert data["username"] == "newuser"

def test_register_user_duplicate(test_client):
    """Teste l'inscription avec un nom d'utilisateur déjà existant."""
    # Créer un utilisateur d'abord
    test_client.post("/register", json={"username": "duplicateuser", "password": "password123"})
    
    # Essayer de créer le même
    response = test_client.post("/register", json={"username": "duplicateuser", "password": "password456"})
    assert response.status_code == 400
    assert response.json() == {"detail": "Username already registered"}

def test_login_user(test_client):
    """Teste la connexion d'un utilisateur."""
    # Créer un utilisateur
    test_client.post("/register", json={"username": "loginuser", "password": "password123"})
    
    # Se connecter
    response = test_client.post(
        "/login", 
        data={"username": "loginuser", "password": "password123"},
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"

def test_login_user_invalid_credentials(test_client):
    """Teste la connexion avec des identifiants incorrects."""
    # Créer un utilisateur
    test_client.post("/register", json={"username": "validuser", "password": "password123"})
    
    # Mauvais mot de passe
    response = test_client.post(
        "/login", 
        data={"username": "validuser", "password": "wrongpassword"},
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Incorrect username or password"

    # Mauvais utilisateur
    response = test_client.post(
        "/login", 
        data={"username": "nonexistent", "password": "password123"},
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    assert response.status_code == 401

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app import app, get_db, Base, get_current_user # Assurez-vous que le nom d'import est correct

# --- Configuration de la base de données de test ---
# Nous utilisons une base de données SQLite en mémoire pour les tests
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
            pass # La fixture db_session gère la fermeture

    # Remplacer la dépendance get_current_user pour simuler un utilisateur connecté
    def override_get_current_user():
        return "testuser"

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user
    
    client = TestClient(app)
    yield client
    
    # Nettoyer les remplacements après le test
    app.dependency_overrides = {}

# --- Tests ---

def test_create_task(test_client):
    """Teste la création d'une nouvelle tâche."""
    response = test_client.post("/tasks", json={"title": "Test Task 1"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test Task 1"
    assert data["owner"] == "testuser"
    assert data["completed"] == False
    assert "id" in data

def test_read_tasks(test_client, db_session):
    """Teste la lecture de toutes les tâches d'un utilisateur."""
    # Créer une tâche de test directement dans la DB
    from app import Task
    db_task = Task(title="Test Task 2", owner="testuser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    
    response = test_client.get("/tasks")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["title"] == "Test Task 2"
    assert data[0]["owner"] == "testuser"

def test_read_tasks_empty(test_client):
    """Teste la lecture des tâches lorsque la liste est vide."""
    response = test_client.get("/tasks")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 0

def test_read_task_not_found(test_client):
    """Teste la lecture d'une tâche qui n'existe pas."""
    response = test_client.get("/tasks/999")
    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}

def test_read_task_not_owner(test_client, db_session):
    """Teste la lecture d'une tâche appartenant à un autre utilisateur."""
    from app import Task
    db_task = Task(title="Other User Task", owner="anotheruser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    
    response = test_client.get(f"/tasks/{db_task.id}")
    assert response.status_code == 403
    assert response.json() == {"detail": "Not authorized to access this task"}

# --- TEST POUR LA PARTIE 4 ---
def test_delete_task(test_client, db_session):
    """Teste la suppression d'une tâche."""
    from app import Task
    db_task = Task(title="Task to delete", owner="testuser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    task_id = db_task.id
    
    # Vérifier que la tâche existe
    assert db_session.get(Task, task_id) is not None
    
    # Supprimer la tâche via l'API
    response = test_client.delete(f"/tasks/{task_id}")
    assert response.status_code == 204
    
    # Vérifier qu'elle est bien supprimée de la DB
    deleted_task = db_session.get(Task, task_id)
    assert deleted_task is None

def test_delete_task_not_found(test_client):
    """Teste la suppression d'une tâche qui n'existe pas."""
    response = test_client.delete("/tasks/999")
    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}

def test_delete_task_not_owner(test_client, db_session):
    """Teste la suppression d'une tâche appartenant à un autre utilisateur."""
    from app import Task
    db_task = Task(title="Other User Task", owner="anotheruser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    
    response = test_client.delete(f"/tasks/{db_task.id}")
    assert response.status_code == 403
    assert response.json() == {"detail": "Not authorized to delete this task"}

# --- TEST POUR LA PARTIE 6 ---
def test_update_task(test_client, db_session):
    """Teste la mise à jour d'une tâche."""
    from app import Task
    db_task = Task(title="Task to update", owner="testuser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    task_id = db_task.id
    
    # Données de mise à jour
    update_data = {"title": "Updated Title", "completed": True}
    
    # Mettre à jour via l'API
    response = test_client.put(f"/tasks/{task_id}", json=update_data)
    assert response.status_code == 200
    data = response.json()
    
    # Vérifier les données retournées
    assert data["title"] == "Updated Title"
    assert data["completed"] == True
    assert data["owner"] == "testuser"
    
    # Vérifier dans la DB
    updated_db_task = db_session.get(Task, task_id)
    assert updated_db_task.title == "Updated Title"
    assert updated_db_task.completed == True

def test_update_task_not_found(test_client):
    """Teste la mise à jour d'une tâche qui n'existe pas."""
    update_data = {"title": "Updated Title", "completed": True}
    response = test_client.put("/tasks/999", json=update_data)
    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}

def test_update_task_not_owner(test_client, db_session):
    """Teste la mise à jour d'une tâche appartenant à un autre utilisateur."""
    from app import Task
    db_task = Task(title="Other User Task", owner="anotheruser", completed=False)
    db_session.add(db_task)
    db_session.commit()
    
    update_data = {"title": "Updated Title", "completed": True}
    response = test_client.put(f"/tasks/{db_task.id}", json=update_data)
    assert response.status_code == 403
    assert response.json() == {"detail": "Not authorized to update this task"}

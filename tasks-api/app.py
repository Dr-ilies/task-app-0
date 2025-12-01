import time
import os
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, ConfigDict
from sqlalchemy import create_engine, Column, Integer, String, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from jose import jwt, JWTError

# --- Configuration ---
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "un_secret_tres_fort_a_changer")
ALGORITHM = "HS256"

# --- Database Configuration ---
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_HOST = os.getenv("DB_HOST", "db")
DB_NAME = os.getenv("DB_NAME", "tasksdb")
# Build DATABASE_URL based on environment
if DB_HOST.startswith("/cloudsql/"):
    # Cloud Run with Cloud SQL Proxy (Unix socket connection)
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@/{DB_NAME}?host={DB_HOST}"
else:
    # Local or GKE (TCP connection)
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}"

Base = declarative_base()
engine = None
SessionLocal = None

app = FastAPI()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# --- Modèles de Données (Task) ---
class Task(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    completed = Column(Boolean, default=False)
    owner = Column(String, index=True) # Username du propriétaire

class TaskCreate(BaseModel):
    title: str

class TaskUpdate(BaseModel):
    title: str
    completed: bool

class TaskOut(BaseModel):
    id: int
    title: str
    completed: bool
    owner: str

    model_config = ConfigDict(from_attributes=True) # <-- Remplacement pour Pydantic v2

# --- Dépendance DB ---
def get_db():
    if SessionLocal is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database not initialized"
        )
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# --- Dépendance d'authentification (validation JWT) ---
async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        return username
    except JWTError:
        raise credentials_exception

# --- Endpoints CRUD pour les Tâches ---
@app.post("/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(
    task: TaskCreate, 
    db: Session = Depends(get_db), 
    current_user: str = Depends(get_current_user)
):
    db_task = Task(title=task.title, owner=current_user, completed=False)
    db.add(db_task)
    db.commit()
    db.refresh(db_task)
    return db_task

@app.get("/tasks", response_model=list[TaskOut])
def read_tasks(
    db: Session = Depends(get_db), 
    current_user: str = Depends(get_current_user)
):
    tasks = db.query(Task).filter(Task.owner == current_user).all()
    return tasks

@app.get("/tasks/{task_id}", response_model=TaskOut)
def read_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    """
    Récupère une tâche spécifique par ID.
    Vérifie que la tâche appartient bien à l'utilisateur connecté.
    """
    db_task = db.query(Task).filter(Task.id == task_id).first()
    if db_task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    if db_task.owner != current_user:
        raise HTTPException(status_code=403, detail="Not authorized to access this task")
    return db_task

@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(
    task_id: int,
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    """
    Supprime une tâche par ID.
    Vérifie que la tâche appartient bien à l'utilisateur connecté avant de la supprimer.
    """
    db_task = db.query(Task).filter(Task.id == task_id).first()

    if db_task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    if db_task.owner != current_user:
        raise HTTPException(status_code=403, detail="Not authorized to delete this task")

    db.delete(db_task)
    db.commit()
    return

@app.put("/tasks/{task_id}", response_model=TaskOut)
def update_task(
    task_id: int,
    task: TaskUpdate,
    db: Session = Depends(get_db),
    current_user: str = Depends(get_current_user)
):
    """
    Met à jour une tâche par ID (titre et statut complété).
    Vérifie que la tâche appartient bien à l'utilisateur connecté avant de la mettre à jour.
    """
    db_task = db.query(Task).filter(Task.id == task_id).first()

    if db_task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    if db_task.owner != current_user:
        raise HTTPException(status_code=403, detail="Not authorized to update this task")

    # Mettre à jour les champs
    db_task.title = task.title
    db_task.completed = task.completed

    db.commit()
    db.refresh(db_task)
    return db_task


@app.get("/health")
def health_check():
    """Health check endpoint for Kubernetes liveness and readiness probes."""
    return {"status": "healthy"}

@app.on_event("startup")
def on_startup():
    global engine, SessionLocal
    # Tentative de connexion à la base de données au démarrage
    max_retries = 10
    retry_delay = 5
    
    for i in range(max_retries):
        try:
            print(f"Connecting to database at {DATABASE_URL}...")
            engine = create_engine(DATABASE_URL)
            SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
            Base.metadata.create_all(bind=engine)
            print("Database connection successful.")
            return
        except Exception as e:
            print(f"Waiting for database... ({i+1}/{max_retries}). Error: {e}")
            time.sleep(retry_delay)
    
    print("Could not connect to database. Application will start but DB endpoints will fail.")

if __name__ == "__main__":
    import uvicorn
    print("Démarrage du serveur Uvicorn...")
    uvicorn.run(app, host="0.0.0.0", port=8000)
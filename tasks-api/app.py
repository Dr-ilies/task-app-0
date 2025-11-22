import os
from fastapi import FastAPI, Depends, HTTPException, status
#from fastapi.security import OAuth2Bearer
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, ConfigDict
from sqlalchemy import create_engine, Column, Integer, String, Boolean, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from jose import JWTError, jwt
import time

# --- Configuration ---
# Variables d'environnement pour la connexion DB
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "password")
DB_HOST = os.environ.get("DB_HOST", "db") # 'db' est le nom du service dans docker-compose
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "tasksdb")

DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Clé secrète JWT (doit être la MÊME que celle de auth-api)
SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "un_secret_tres_fort_a_changer")
ALGORITHM = "HS256"

Base = declarative_base()
engine = None
SessionLocal = None

# Attente active pour la DB (simple pour le TP, en prod utiliser "depends_on" ou un script)
max_retries = 10
retry_delay = 5
for i in range(max_retries):
    try:
        engine = create_engine(DATABASE_URL)
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        Base.metadata.create_all(bind=engine)
        print("Connexion à la base de données réussie.")
        break
    except Exception as e:
        print(f"Attente de la base de données... ({i+1}/{max_retries}). Erreur: {e}")
        time.sleep(retry_delay)

if engine is None:
    print("Échec de la connexion à la base de données après plusieurs tentatives.")
    exit(1)


app = FastAPI()
#oauth2_scheme = OAuth2Bearer(tokenUrl="token") # L'URL n'est pas utilisée ici
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token") # L'URL n'est pas utilisée ici

# --- Modèles de Données (Task) ---
class Task(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    completed = Column(Boolean, default=False)
    owner = Column(String, index=True) # Username du propriétaire

class TaskCreate(BaseModel):
    title: str

class TaskOut(BaseModel):
    id: int
    title: str
    completed: bool
    owner: str

    model_config = ConfigDict(from_attributes=True) # <-- Remplacement pour Pydantic v2

    #class Config:   #      <-- ANCIENNE METHODE
    #    orm_mode = True # Permet de mapper le modèle SQLAlchemy

# --- Dépendance DB ---
def get_db():
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

@app.on_event("startup")
def on_startup():
    # Créer les tables au démarrage de l'application
    Base.metadata.create_all(bind=engine)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
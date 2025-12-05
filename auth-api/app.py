import time
import os
from urllib.parse import quote_plus
from datetime import datetime, timedelta
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, ConfigDict
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from passlib.context import CryptContext
from jose import jwt

# --- Configuration ---
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "un_secret_tres_fort_a_changer")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# --- Database Configuration ---
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_HOST = os.getenv("DB_HOST", "db")
DB_NAME = os.getenv("DB_NAME", "tasksdb")
# Build DATABASE_URL based on environment
# URL-encode the password to handle special characters like @
DB_PASSWORD_ENCODED = quote_plus(DB_PASSWORD)
if DB_HOST.startswith("/cloudsql/"):
    # Cloud Run with Cloud SQL Proxy (Unix socket connection)
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD_ENCODED}@/{DB_NAME}?host={DB_HOST}"
else:
    # Local or GKE (TCP connection)
    DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD_ENCODED}@{DB_HOST}/{DB_NAME}"

Base = declarative_base()
engine = None
SessionLocal = None

app = FastAPI()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- Modèles de Données (User) ---
class UserInDB(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)

class UserCreate(BaseModel):
    username: str
    password: str

    model_config = ConfigDict(from_attributes=True) # <-- pour Pydantic v2

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

# --- Fonctions d'Authentification ---
def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

# --- Endpoints ---
@app.post("/register", status_code=status.HTTP_201_CREATED)
def register_user(user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(UserInDB).filter(UserInDB.username == user.username).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Username already registered")
    hashed_password = get_password_hash(user.password)
    db_user = UserInDB(username=user.username, hashed_password=hashed_password)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return {"username": db_user.username}

@app.post("/login")
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(UserInDB).filter(UserInDB.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/init-db")
def init_db():
    try:
        global engine
        
        # --- DEBUG LOGGING ---
        pwd_len = len(DB_PASSWORD) if DB_PASSWORD else 0
        pwd_start = DB_PASSWORD[0] if DB_PASSWORD else "None"
        pwd_end = DB_PASSWORD[-1] if DB_PASSWORD else "None"
        print(f"DEBUG: User: {DB_USER}, Password Len: {pwd_len}, Start: '{pwd_start}', End: '{pwd_end}'")
        # ---------------------

        if engine is None:
             engine = create_engine(DATABASE_URL)
        Base.metadata.create_all(bind=engine)
        return {"status": "success", "message": "Tables created"}
    except Exception as e:
        print(f"DEBUG ERROR: {e}")
        raise HTTPException(status_code=500, detail=str(e))

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
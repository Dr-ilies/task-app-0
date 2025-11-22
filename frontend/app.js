// URLs des API
// Note: Le /api/ et /auth/ sont gérés par Nginx (voir nginx.conf)
const AUTH_API_URL = '/auth';
const TASKS_API_URL = '/api';

// Éléments du DOM
const authSection = document.getElementById('auth-section');
const tasksSection = document.getElementById('tasks-section');
const authMsg = document.getElementById('auth-msg');

const loginBtn = document.getElementById('login-btn');
const registerBtn = document.getElementById('register-btn');
const logoutBtn = document.getElementById('logout-btn');

const addTaskBtn = document.getElementById('add-task-btn');
const tasksList = document.getElementById('tasks-list');

let token = localStorage.getItem('token');

// --- Logique d'affichage ---
function showAuth() {
    authSection.classList.remove('hidden');
    tasksSection.classList.add('hidden');
    token = null;
    localStorage.removeItem('token');
}

function showTasks() {
    authSection.classList.add('hidden');
    tasksSection.classList.remove('hidden');
    loadTasks();
}

// --- Logique d'Authentification ---
registerBtn.onclick = async () => {
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    try {
        const response = await fetch(`${AUTH_API_URL}/register`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });
        if (response.status === 201) {
            authMsg.textContent = 'Inscription réussie ! Connectez-vous.';
        } else {
            const data = await response.json();
            authMsg.textContent = `Erreur: ${data.detail}`;
        }
    } catch (e) { authMsg.textContent = 'Erreur réseau.'; }
};

loginBtn.onclick = async () => {
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    authMsg.textContent = '';
    
    // Note: l'API attend des 'form data' pour OAuth2
    const formData = new URLSearchParams();
    formData.append('username', username);
    formData.append('password', password);

    try {
        const response = await fetch(`${AUTH_API_URL}/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: formData
        });
        if (response.ok) {
            const data = await response.json();
            token = data.access_token;
            localStorage.setItem('token', token);
            showTasks();
        } else {
            authMsg.textContent = 'Échec de la connexion.';
        }
    } catch (e) { authMsg.textContent = 'Erreur réseau.'; }
};

logoutBtn.onclick = () => showAuth();

// --- Logique des Tâches ---
async function loadTasks() {
    if (!token) return;
    try {
        const response = await fetch(`${TASKS_API_URL}/tasks`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (response.status === 401) return showAuth(); // Token expiré
        
        const tasks = await response.json();
        tasksList.innerHTML = '';
        tasks.forEach(task => {
            const li = document.createElement('li');
            li.textContent = task.title + (task.completed ? ' (Terminée)' : '');
            tasksList.appendChild(li);
        });
    } catch (e) { console.error('Erreur chargement tâches:', e); }
}

addTaskBtn.onclick = async () => {
    if (!token) return;
    const title = document.getElementById('task-title').value;
    if (!title) return;

    try {
        const response = await fetch(`${TASKS_API_URL}/tasks`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ title })
        });
        if (response.status === 201) {
            document.getElementById('task-title').value = '';
            loadTasks();
        } else {
            console.error('Erreur ajout tâche');
        }
    } catch (e) { console.error('Erreur réseau ajout tâche:', e); }
};

// --- Initialisation ---
if (token) {
    showTasks();
} else {
    showAuth();
}
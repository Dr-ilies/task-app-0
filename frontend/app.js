// URLs des API
// Note: Le /api/ et /auth/ sont gérés par Nginx
const AUTH_API_URL = '/auth';
const TASKS_API_URL = '/api';

// Éléments du DOM
const authSection = document.getElementById('auth-section');
const tasksSection = document.getElementById('tasks-section');
const authMsg = document.getElementById('auth-msg');
const taskMsg = document.getElementById('task-msg'); // Ajout pour les messages d'erreur de tâches

const loginBtn = document.getElementById('login-btn');
const registerBtn = document.getElementById('register-btn');
const logoutBtn = document.getElementById('logout-btn');

const addTaskBtn = document.getElementById('add-task-btn');
const tasksList = document.getElementById('tasks-list');
const taskTitleInput = document.getElementById('task-title');

let token = localStorage.getItem('token');

// --- Logique d'affichage ---
function showAuth(message = '') {
    authSection.classList.remove('hidden');
    tasksSection.classList.add('hidden');
    token = null;
    localStorage.removeItem('token');
    authMsg.textContent = message;
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
}

function showTasks() {
    authSection.classList.add('hidden');
    tasksSection.classList.remove('hidden');
    taskMsg.textContent = ''; // Effacer les anciens messages
    loadTasks();
}

// --- Logique d'Authentification ---
registerBtn.onclick = async () => {
    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    if (!username || !password) {
        authMsg.textContent = 'Veuillez remplir tous les champs.';
        return;
    }
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

    if (!username || !password) {
        authMsg.textContent = 'Veuillez remplir tous les champs.';
        return;
    }

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
            authMsg.textContent = 'Échec de la connexion. Vérifiez vos identifiants.';
        }
    } catch (e) { authMsg.textContent = 'Erreur réseau.'; }
};

logoutBtn.onclick = () => showAuth('Déconnexion réussie.');

// --- Logique des Tâches ---

async function loadTasks() {
    if (!token) return;
    try {
        const response = await fetch(`${TASKS_API_URL}/tasks`, {
            headers: { 'Authorization': `Bearer ${token}` }
        });
        if (response.status === 401) return showAuth('Session expirée. Veuillez vous reconnecter.');

        const tasks = await response.json();
        console.log(tasks); // Log tasks to the console
        tasksList.innerHTML = ''; // Nettoyer la liste
        tasks.forEach(task => {
            tasksList.appendChild(createTaskElement(task));
        });
    } catch (e) {
        console.error('Erreur chargement tâches:', e);
        taskMsg.textContent = 'Erreur lors du chargement des tâches.';
    }
}

// Fonction pour créer un élément LI pour une tâche
function createTaskElement(task) {
    console.log('Creating task element:', task); // Log the task object
    const li = document.createElement('li');
    li.dataset.taskId = task.id; // Stocker l'ID de la tâche

    // Checkbox pour l'état "complété"
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = task.completed;
    checkbox.classList.add('task-checkbox');
    checkbox.addEventListener('change', () => handleUpdateTask(task.id, li.querySelector('.task-title').textContent, checkbox.checked));

    // Titre de la tâche (cliquable pour modifier)
    const titleSpan = document.createElement('span');
    titleSpan.textContent = task.title;
    titleSpan.classList.add('task-title');
    if (task.completed) {
        titleSpan.classList.add('completed');
    }
    titleSpan.addEventListener('click', () => editTaskTitle(li));

    // Bouton Supprimer
    const deleteBtn = document.createElement('button');
    deleteBtn.textContent = 'Supprimer';
    deleteBtn.classList.add('delete-btn');
    deleteBtn.addEventListener('click', (e) => {
        e.stopPropagation(); // Empêcher l'événement de se propager au li
        handleDeleteTask(task.id, li);
    });

    li.appendChild(checkbox);
    li.appendChild(titleSpan);
    li.appendChild(deleteBtn);

    return li;
}

// --- NOUVELLE FONCTIONNALITÉ (PARTIE 4) ---
async function handleDeleteTask(taskId, liElement) {
    if (!token) return showAuth('Session expirée.');
    if (!confirm('Êtes-vous sûr de vouloir supprimer cette tâche ?')) return;

    try {
        const response = await fetch(`${TASKS_API_URL}/tasks/${taskId}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${token}` }
        });

        if (response.status === 204) {
            // Succès, supprimer l'élément du DOM
            liElement.remove();
            taskMsg.textContent = 'Tâche supprimée.';
        } else if (response.status === 401) {
            showAuth('Session expirée.');
        } else {
            taskMsg.textContent = 'Erreur lors de la suppression.';
        }
    } catch (e) {
        console.error('Erreur réseau suppression:', e);
        taskMsg.textContent = 'Erreur réseau lors de la suppression.';
    }
}

// --- NOUVELLE FONCTIONNALITÉ (PARTIE 6) ---
// Fonction pour gérer la mise à jour (titre ou checkbox)
async function handleUpdateTask(taskId, title, completed) {
    if (!token) return showAuth('Session expirée.');

    try {
        const response = await fetch(`${TASKS_API_URL}/tasks/${taskId}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ title, completed })
        });

        if (response.ok) {
            const updatedTask = await response.json();
            // Mettre à jour le DOM
            const li = tasksList.querySelector(`li[data-task-id="${taskId}"]`);
            if (li) {
                const titleSpan = li.querySelector('.task-title');
                titleSpan.textContent = updatedTask.title;
                titleSpan.classList.toggle('completed', updatedTask.completed);
                li.querySelector('.task-checkbox').checked = updatedTask.completed;
            }
            taskMsg.textContent = 'Tâche mise à jour.';
        } else {
            taskMsg.textContent = 'Erreur lors de la mise à jour.';
            // Optionnel : recharger les tâches pour annuler les changements locaux
            loadTasks();
        }
    } catch (e) {
        console.error('Erreur réseau mise à jour:', e);
        taskMsg.textContent = 'Erreur réseau lors de la mise à jour.';
    }
}

// Fonction pour rendre le titre éditable
function editTaskTitle(li) {
    const titleSpan = li.querySelector('.task-title');
    const currentTitle = titleSpan.textContent;

    // Remplacer le span par un input
    const input = document.createElement('input');
    input.type = 'text';
    input.value = currentTitle;
    input.classList.add('edit-input');

    // Remplacer
    li.replaceChild(input, titleSpan);
    input.focus();

    // Gérer la sauvegarde (quand on quitte le focus ou appuie sur Entrée)
    const save = async () => {
        const newTitle = input.value.trim();
        const taskId = li.dataset.taskId;
        const isCompleted = li.querySelector('.task-checkbox').checked;

        if (newTitle && newTitle !== currentTitle) {
            // Remplacer l'input par le span avant l'appel réseau (optimiste)
            titleSpan.textContent = newTitle;
            li.replaceChild(titleSpan, input);
            // Appeler l'API de mise à jour
            await handleUpdateTask(taskId, newTitle, isCompleted);
        } else {
            // Annuler, juste remettre le span
            titleSpan.textContent = currentTitle;
            li.replaceChild(titleSpan, input);
        }
    };

    input.addEventListener('blur', save);
    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            input.blur(); // Déclenche l'événement blur (et donc 'save')
        } else if (e.key === 'Escape') {
            input.value = currentTitle; // Annuler les changements
            input.blur(); // Déclenche l'événement blur
        }
    });
}


// --- Logique d'Ajout de Tâche ---
addTaskBtn.onclick = async () => {
    if (!token) return showAuth('Session expirée.');
    const title = taskTitleInput.value;
    if (!title) {
        taskMsg.textContent = 'Veuillez entrer un titre pour la tâche.';
        return;
    }

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
            taskTitleInput.value = ''; // Vider le champ
            taskMsg.textContent = 'Tâche ajoutée !';
            loadTasks(); // Recharger la liste
        } else if (response.status === 401) {
            showAuth('Session expirée.');
        } else {
            taskMsg.textContent = 'Erreur lors de l\'ajout de la tâche.';
        }
    } catch (e) {
        console.error('Erreur réseau ajout tâche:', e);
        taskMsg.textContent = 'Erreur réseau lors de l\'ajout.';
    }
};

// --- Initialisation ---
if (token) {
    // Optionnel : on pourrait valider le token ici avant de montrer les tâches
    showTasks();
} else {
    showAuth();
}
// ─── State ───────────────────────────────────────────────────────────────────
let globalData    = { nodes: [], stacks: [], services: [], tasks: [] };
let activeStackId = null;
let originalCompose = '';

// ─── Fetch & Render ───────────────────────────────────────────────────────────
async function fetchData() {
    try {
        const r = await fetch('/api/state');
        if (!r.ok) return;
        globalData = await r.json();
        renderDashboard(globalData);
        document.getElementById('last-refresh').textContent =
            'Refreshed: ' + new Date().toLocaleTimeString();
    } catch (e) {
        console.error('Error fetching state:', e);
    }
}

function renderDashboard(data) {
    // Stats
    const tasks    = data.tasks || [];
    const running  = tasks.filter(t => t.status === 'running').length;
    document.getElementById('stats').innerHTML = `
        <div class="stat-card"><h3>Nodes</h3><div class="value">${(data.nodes||[]).length}</div></div>
        <div class="stat-card"><h3>Stacks</h3><div class="value">${(data.stacks||[]).length}</div></div>
        <div class="stat-card"><h3>Services</h3><div class="value">${(data.services||[]).length}</div></div>
        <div class="stat-card"><h3>Tasks</h3><div class="value">${tasks.length}</div></div>
        <div class="stat-card"><h3>Running</h3><div class="value" style="color:#2ea043">${running}</div></div>
    `;

    // Stacks
    document.querySelector('#stacks-table tbody').innerHTML =
        (data.stacks||[]).map(s => `
        <tr>
            <td><code>${s.id.substring(0,8)}</code></td>
            <td><strong>${s.name}</strong></td>
            <td>${new Date(s.created_at).toLocaleString()}</td>
            <td>
                <button class="btn btn-info"    onclick="openComposeModal('${s.id}','${s.name}')">Edit YAML</button>
                <button class="btn btn-warning" onclick="redeployStackById('${s.id}')">Redeploy</button>
                <button class="btn btn-danger"  onclick="deleteStack('${s.id}')">Delete</button>
            </td>
        </tr>`).join('');

    // Nodes
    document.querySelector('#nodes-table tbody').innerHTML =
        (data.nodes||[]).map(n => `
        <tr>
            <td><code>${n.id.substring(0,8)}</code></td>
            <td>${n.ip}</td>
            <td><span class="status-tag st-${n.role}">${n.role}</span></td>
            <td><span class="status-tag st-${n.status}">${n.status}</span></td>
        </tr>`).join('');

    // Tasks
    document.querySelector('#tasks-table tbody').innerHTML =
        tasks.map(t => {
            const svc  = (data.services||[]).find(s => s.id === t.service_id) || {name:'unknown', image:'-'};
            const node = (data.nodes||[]).find(n => n.id === t.node_id) || {id:'unknown'};
            return `
            <tr>
                <td><code>${t.id.substring(0,8)}</code></td>
                <td><strong>${svc.name}</strong><br><small style="color:var(--text-secondary)">${svc.image||''}</small></td>
                <td><code>${t.container_name || '-'}</code></td>
                <td><code>${node.id.substring(0,8)}</code></td>
                <td><span class="status-tag st-${t.status}">${t.status}</span></td>
                <td>${t.container_ip || '-'}</td>
                <td><button class="btn btn-danger" onclick="stopTask('${t.id}')">Stop</button></td>
            </tr>`;
        }).join('');
}

// ─── Stack Actions ────────────────────────────────────────────────────────────
async function deleteStack(id) {
    if (!confirm('Delete this stack and stop all its containers?')) return;
    const r = await fetch('/api/stack/' + id, { method: 'DELETE' });
    toast(r.ok ? 'Stack deleted and containers stopped.' : 'Failed to delete stack.', r.ok);
    fetchData();
}

async function redeployStackById(id) {
    if (!confirm('Stop existing containers and redeploy this stack?')) return;
    showLoading(id);
    const r = await fetch('/api/stack/' + id + '/redeploy', { method: 'POST' });
    toast(r.ok ? 'Stack redeployed!' : 'Redeploy failed.', r.ok);
    fetchData();
}

async function stopTask(id) {
    if (!confirm('Stop this container/task?')) return;
    const r = await fetch('/api/task/' + id, { method: 'DELETE' });
    toast(r.ok ? 'Task stopped.' : 'Failed to stop task.', r.ok);
    fetchData();
}

// ─── Compose Editor Modal ─────────────────────────────────────────────────────
async function openComposeModal(id, name) {
    activeStackId = id;
    document.getElementById('compose-modal-title').textContent = 'Edit Compose: ' + name;
    document.getElementById('compose-modal').style.display = 'flex';

    const r = await fetch('/api/stack/' + id + '/compose');
    const data = await r.json();
    const compose = data.compose || '';
    document.getElementById('compose-textarea').value = compose;
    originalCompose = compose;
}

function closeComposeModal() {
    document.getElementById('compose-modal').style.display = 'none';
    activeStackId = null;
}

function resetCompose() {
    document.getElementById('compose-textarea').value = originalCompose;
}

async function saveCompose() {
    if (!activeStackId) return;
    const compose = document.getElementById('compose-textarea').value;
    const r = await fetch('/api/stack/' + activeStackId + '/compose', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ compose })
    });
    if (r.ok) {
        originalCompose = compose;
        toast('Compose saved successfully.', true);
    } else {
        toast('Failed to save compose.', false);
    }
}

async function redeployStack() {
    if (!activeStackId) return;
    // Save first, then redeploy
    await saveCompose();
    const r = await fetch('/api/stack/' + activeStackId + '/redeploy', { method: 'POST' });
    toast(r.ok ? 'Stack redeployed!' : 'Redeploy failed.', r.ok);
    closeComposeModal();
    fetchData();
}

function showLoading(stackId) {
    // Visually mark row as redeploying
    const rows = document.querySelectorAll('#stacks-table tbody tr');
    rows.forEach(row => {
        if (row.innerHTML.includes(stackId.substring(0,8))) {
            row.style.opacity = '0.5';
        }
    });
}

// ─── Toast ────────────────────────────────────────────────────────────────────
function toast(msg, ok = true) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.style.display = 'block';
    el.style.borderColor = ok ? '#2ea043' : '#da3633';
    el.style.color = ok ? '#2ea043' : '#da3633';
    setTimeout(() => { el.style.display = 'none'; }, 3500);
}

// ─── Init ─────────────────────────────────────────────────────────────────────
fetchData();
setInterval(fetchData, 5000);

// Close modal on backdrop click
document.getElementById('compose-modal').addEventListener('click', function(e) {
    if (e.target === this) closeComposeModal();
});

async function fetchData() {
    try {
        const response = await fetch('/api/state');
        const data = await response.json();
        renderDashboard(data);
    } catch (error) {
        console.error("Error fetching state:", error);
    }
}

let globalStacks = [];

function renderDashboard(data) {
    globalStacks = data.stacks;
    // Render Stats
    const statsHtml = `
        <div class="stat-card"><h3>Nodes</h3><div class="value">${data.nodes.length}</div></div>
        <div class="stat-card"><h3>Stacks</h3><div class="value">${data.stacks.length}</div></div>
        <div class="stat-card"><h3>Services</h3><div class="value">${data.services.length}</div></div>
        <div class="stat-card"><h3>Tasks</h3><div class="value">${data.tasks.length}</div></div>
    `;
    document.getElementById('stats').innerHTML = statsHtml;

    // Render Stacks
    const stacksTbody = document.querySelector('#stacks-table tbody');
    stacksTbody.innerHTML = data.stacks.map(s => `
        <tr>
            <td>${s.id.substring(0,8)}</td>
            <td><strong>${s.name}</strong></td>
            <td>${new Date(s.created_at).toLocaleString()}</td>
            <td>
                <button class="btn btn-info" onclick="viewCompose('${s.id}')">View YAML</button>
                <button class="btn btn-danger" onclick="deleteStack('${s.id}')">Delete</button>
            </td>
        </tr>
    `).join('');

    // Render Nodes
    const nodesTbody = document.querySelector('#nodes-table tbody');
    nodesTbody.innerHTML = data.nodes.map(n => `
        <tr>
            <td>${n.id.substring(0,8)}</td>
            <td>${n.ip}</td>
            <td><span class="status ${n.role}">${n.role}</span></td>
            <td><span class="status ${n.status}">${n.status}</span></td>
        </tr>
    `).join('');

    // Render Tasks
    const tasksTbody = document.querySelector('#tasks-table tbody');
    tasksTbody.innerHTML = data.tasks.map(t => {
        const svc = data.services.find(s => s.id === t.service_id) || {name: 'unknown'};
        const node = data.nodes.find(n => n.id === t.node_id) || {id: 'unknown'};
        return `
        <tr>
            <td>${t.id.substring(0,8)}</td>
            <td><strong>${svc.name}</strong></td>
            <td>${node.id.substring(0,8)}</td>
            <td><span class="status ${t.status}">${t.status}</span></td>
            <td>${t.container_ip || '-'}</td>
            <td><button class="btn btn-danger" onclick="stopTask('${t.id}')">Stop</button></td>
        </tr>
    `}).join('');
}

async function deleteStack(id) {
    if(!confirm("Are you sure you want to delete this stack?")) return;
    try {
        await fetch('/api/stack/'+id, { method: 'DELETE' });
        fetchData();
    } catch (e) { alert("Failed to delete stack"); }
}

async function stopTask(id) {
    if(!confirm("Are you sure you want to stop this task? (The service might recreate it)")) return;
    try {
        await fetch('/api/task/'+id, { method: 'DELETE' });
        fetchData();
    } catch (e) { alert("Failed to stop task"); }
}

function viewCompose(id) {
    const stack = globalStacks.find(s => s.id === id);
    if(stack) {
        document.getElementById('compose-textarea').value = stack.raw_compose_file;
        document.getElementById('compose-modal').style.display = 'flex';
    }
}

function closeComposeModal() {
    document.getElementById('compose-modal').style.display = 'none';
}

// Initial fetch and poll every 5 seconds
fetchData();
setInterval(fetchData, 5000);

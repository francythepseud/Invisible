package main

const dashboardHTML = `<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Invisible — Admin</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0a0a0a;color:#e0e0e0;min-height:100vh}
  .login{display:flex;align-items:center;justify-content:center;min-height:100vh}
  .login-box{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:16px;padding:40px;width:360px}
  .login-box h1{font-size:22px;margin-bottom:8px;color:#fff}
  .login-box p{font-size:13px;color:#666;margin-bottom:24px}
  input{width:100%;padding:12px 14px;background:#252525;border:1px solid #333;border-radius:10px;color:#fff;font-size:14px;outline:none}
  input:focus{border-color:#2196F3}
  .btn{width:100%;padding:12px;background:#2196F3;border:none;border-radius:10px;color:#fff;font-size:14px;font-weight:600;cursor:pointer;margin-top:12px}
  .btn:hover{background:#1976D2}
  .btn-sm{padding:6px 14px;border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;border:none}
  .btn-danger{background:rgba(255,82,82,0.15);color:#ff5252;border:1px solid rgba(255,82,82,0.3)}
  .btn-danger:hover{background:rgba(255,82,82,0.25)}
  .btn-success{background:rgba(76,175,80,0.15);color:#4caf50;border:1px solid rgba(76,175,80,0.3)}
  .btn-success:hover{background:rgba(76,175,80,0.25)}
  .btn-gray{background:rgba(255,255,255,0.08);color:#aaa;border:1px solid rgba(255,255,255,0.1)}
  .btn-gray:hover{background:rgba(255,255,255,0.12)}
  .app{display:none;padding:24px;max-width:1100px;margin:0 auto}
  .header{display:flex;align-items:center;justify-content:space-between;margin-bottom:28px}
  .header h1{font-size:20px;color:#fff}
  .header span{font-size:12px;color:#666}
  .tabs{display:flex;gap:8px;margin-bottom:20px}
  .tab{padding:8px 18px;border-radius:8px;font-size:13px;font-weight:500;cursor:pointer;border:1px solid #2a2a2a;background:#1a1a1a;color:#888}
  .tab.active{background:#2196F3;border-color:#2196F3;color:#fff}
  .card{background:#1a1a1a;border:1px solid #252525;border-radius:14px;padding:20px;margin-bottom:16px}
  .card h2{font-size:14px;font-weight:600;color:#fff;margin-bottom:16px}
  .add-form{display:flex;gap:10px;flex-wrap:wrap}
  .add-form input{flex:1;min-width:180px}
  .add-form .btn{width:auto;margin-top:0;padding:12px 20px}
  table{width:100%;border-collapse:collapse;font-size:13px}
  th{text-align:left;padding:10px 12px;color:#666;font-weight:500;border-bottom:1px solid #252525}
  td{padding:10px 12px;border-bottom:1px solid #1e1e1e;vertical-align:middle}
  tr:last-child td{border-bottom:none}
  .hash{font-family:monospace;font-size:11px;color:#666}
  .badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:11px;font-weight:600}
  .badge-on{background:rgba(76,175,80,0.15);color:#4caf50}
  .badge-off{background:rgba(255,255,255,0.06);color:#555}
  .badge-gdpr{background:rgba(33,150,243,0.15);color:#2196F3}
  .actions{display:flex;gap:6px}
  .empty{text-align:center;padding:40px;color:#444;font-size:13px}
  .err-msg{font-size:12px;color:#ff5252;max-width:300px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .section{display:none}
  .section.active{display:block}
  .stats{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:20px}
  .stat{background:#1a1a1a;border:1px solid #252525;border-radius:12px;padding:16px;text-align:center}
  .stat-n{font-size:28px;font-weight:700;color:#2196F3}
  .stat-l{font-size:12px;color:#666;margin-top:4px}
</style>
</head>
<body>

<div class="login" id="loginPage">
  <div class="login-box">
    <h1>🔐 Invisible Admin</h1>
    <p>Inserisci il token di accesso</p>
    <input type="password" id="tokenInput" placeholder="Admin token" onkeydown="if(event.key==='Enter')doLogin()">
    <button type="button" class="btn" onclick="doLogin()">Accedi</button>
    <p id="loginErr" style="color:#ff5252;font-size:12px;margin-top:10px"></p>
  </div>
</div>

<div class="app" id="appPage">
  <div class="header">
    <h1>Invisible Admin</h1>
    <span id="tokenDisplay"></span>
  </div>

  <div class="tabs">
    <div class="tab active" onclick="showTab('users')">👥 Utenti</div>
    <div class="tab" onclick="showTab('errors')">⚠️ Errori App</div>
  </div>

  <!-- UTENTI -->
  <div class="section active" id="sec-users">
    <div class="stats">
      <div class="stat"><div class="stat-n" id="statTotal">0</div><div class="stat-l">Totale utenti</div></div>
      <div class="stat"><div class="stat-n" id="statActive">0</div><div class="stat-l">Attivi</div></div>
      <div class="stat"><div class="stat-n" id="statGdpr">0</div><div class="stat-l">GDPR accettato</div></div>
    </div>
    <div class="card">
      <h2>Aggiungi utente</h2>
      <div class="add-form">
        <input type="text" id="newName" placeholder="Nome (es. Mario Rossi)" onkeydown="if(event.key==='Enter')addUser()">
        <input type="text" id="newHash" placeholder="Identity hash (64 caratteri hex)" onkeydown="if(event.key==='Enter')addUser()">
        <input type="text" id="newNotes" placeholder="Note (opzionale)" onkeydown="if(event.key==='Enter')addUser()">
        <button type="button" class="btn" style="width:auto;margin-top:0;padding:12px 20px" onclick="addUser()">+ Aggiungi</button>
      </div>
      <p id="addErr" style="color:#ff5252;font-size:12px;margin-top:8px"></p>
    </div>
    <div class="card">
      <h2>Utenti autorizzati</h2>
      <table id="usersTable">
        <thead><tr><th>Nome</th><th>Identity Hash</th><th>Online</th><th>Stato</th><th>GDPR</th><th>Attivato</th><th>Scadenza</th><th>Azioni</th></tr></thead>
        <tbody id="usersBody"></tbody>
      </table>
    </div>
  </div>

  <!-- ERRORI -->
  <div class="section" id="sec-errors">
    <div class="card">
      <h2>Log errori app <button class="btn-sm btn-gray" style="margin-left:8px" onclick="loadErrors()">↻ Aggiorna</button></h2>
      <table>
        <thead><tr><th>Data</th><th>Dispositivo</th><th>OS</th><th>Versione</th><th>Tipo</th><th>Messaggio</th></tr></thead>
        <tbody id="errorsBody"></tbody>
      </table>
    </div>
  </div>
</div>

<script>
let TOKEN = sessionStorage.getItem('admin_token') || '';
let _refreshTimer = null;

function startAutoRefresh() {
  if (_refreshTimer) return;
  _refreshTimer = setInterval(() => { if (TOKEN) loadUsers(); }, 30000);
}

function stopAutoRefresh() {
  clearInterval(_refreshTimer);
  _refreshTimer = null;
}

if (TOKEN) {
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => {
      if (r.status === 200) {
        document.getElementById('loginPage').style.display = 'none';
        document.getElementById('appPage').style.display = 'block';
        document.getElementById('tokenDisplay').textContent = 'Token: ' + TOKEN.substring(0,8) + '...';
        loadUsers(); startAutoRefresh();
      } else { sessionStorage.removeItem('admin_token'); TOKEN = ''; }
    }).catch(() => {});
}

function doLogin() {
  const t = document.getElementById('tokenInput').value.trim();
  if (!t) return;
  TOKEN = t;
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => {
      if (r.status === 401) { document.getElementById('loginErr').textContent = 'Token non valido'; return; }
      sessionStorage.setItem('admin_token', TOKEN);
      document.getElementById('loginPage').style.display = 'none';
      document.getElementById('appPage').style.display = 'block';
      document.getElementById('tokenDisplay').textContent = 'Token: ' + TOKEN.substring(0,8) + '...';
      loadUsers(); startAutoRefresh();
    });
}

function showTab(tab) {
  document.querySelectorAll('.tab').forEach((t,i) => t.classList.toggle('active', ['users','errors'][i] === tab));
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.getElementById('sec-'+tab).classList.add('active');
  if (tab === 'errors') loadErrors();
}

function loadUsers() {
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(users => {
      const body = document.getElementById('usersBody');
      document.getElementById('statTotal').textContent = users.length;
      document.getElementById('statActive').textContent = users.filter(u=>u.enabled).length;
      document.getElementById('statGdpr').textContent = users.filter(u=>u.gdpr_accepted).length;
      if (!users.length) { body.innerHTML = '<tr><td colspan="8" class="empty">Nessun utente</td></tr>'; return; }
      body.innerHTML = users.map(function(u) {
        var onlineDot = u.online
          ? '<span title="Online ora" style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#4caf50;box-shadow:0 0 6px #4caf50"></span>'
          : '<span title="' + (u.last_seen_at ? 'Visto: ' + u.last_seen_at : 'Mai connesso') + '" style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#333;border:1px solid #444"></span>';
        var expiry = '<span style="color:#444;font-size:11px">—</span>';
        if (u.expires_at) {
          var daysLeft = Math.ceil((new Date(u.expires_at) - new Date()) / 86400000);
          var color = daysLeft < 30 ? '#ff9800' : '#555';
          expiry = '<span style="color:' + color + ';font-size:12px">' + u.expires_at + (daysLeft < 30 ? ' (' + daysLeft + 'gg)' : '') + '</span>';
        }
        var rowStyle = (!u.enabled && u.gdpr_accepted) ? 'background:rgba(33,150,243,0.04);' : '';
        var pendingBadge = (!u.enabled && u.gdpr_accepted) ? ' <span style="font-size:10px;color:#2196F3;font-weight:600">IN ATTESA</span>' : '';
        return '<tr style="' + rowStyle + '">' +
          '<td><strong>' + esc(u.name) + '</strong>' + pendingBadge + (u.notes ? '<br><span style="color:#555;font-size:11px">' + esc(u.notes) + '</span>' : '') + '</td>' +
          '<td class="hash">' + u.identity_hash.substring(0,16) + '...</td>' +
          '<td style="text-align:center">' + onlineDot + '</td>' +
          '<td><span class="badge ' + (u.enabled ? 'badge-on' : 'badge-off') + '">' + (u.enabled ? 'ATTIVO' : 'DISATTIVO') + '</span></td>' +
          '<td>' + (u.gdpr_accepted ? '<span class="badge badge-gdpr">✓ GDPR</span>' : '<span style="color:#444;font-size:11px">—</span>') + '</td>' +
          '<td style="color:#666;font-size:12px">' + (u.enabled_at || '—') + '</td>' +
          '<td>' + expiry + '</td>' +
          '<td><div class="actions">' +
            '<button type="button" class="btn-sm ' + (u.enabled ? 'btn-danger' : 'btn-success') + '" onclick="toggleUser(\'' + u.identity_hash + '\')">' + (u.enabled ? 'Disattiva' : 'Attiva') + '</button>' +
            '<button type="button" class="btn-sm btn-danger" onclick="deleteUser(\'' + u.identity_hash + '\',\'' + esc(u.name) + '\')">Elimina</button>' +
          '</div></td>' +
          '</tr>';
      }).join('');
    });
}

function addUser() {
  const name = document.getElementById('newName').value.trim();
  const hash = document.getElementById('newHash').value.trim();
  const notes = document.getElementById('newNotes').value.trim();
  const err = document.getElementById('addErr');
  if (!name || !hash) { err.textContent = 'Nome e hash obbligatori'; return; }
  if (hash.length < 16) { err.textContent = 'Codice non valido (troppo corto)'; return; }
  err.textContent = '';
  fetch('/admin/api/users', {
    method:'POST',
    headers:{'X-Admin-Token':TOKEN,'Content-Type':'application/json'},
    body: JSON.stringify({identity_hash:hash, name, notes})
  }).then(r => {
    if (!r.ok) { err.textContent = 'Errore aggiunta'; return; }
    document.getElementById('newName').value = '';
    document.getElementById('newHash').value = '';
    document.getElementById('newNotes').value = '';
    loadUsers();
  });
}

function toggleUser(hash) {
  fetch('/admin/api/users/'+hash+'/toggle', {
    method:'POST', headers:{'X-Admin-Token':TOKEN}
  }).then(() => loadUsers());
}

function deleteUser(hash, name) {
  if (!confirm('Eliminare '+name+'? L\'utente non potrà più usare l\'app.')) return;
  fetch('/admin/api/users/'+hash, {
    method:'DELETE', headers:{'X-Admin-Token':TOKEN}
  }).then(() => loadUsers());
}

function loadErrors() {
  fetch('/admin/api/errors', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(logs => {
      const body = document.getElementById('errorsBody');
      if (!logs.length) { body.innerHTML = '<tr><td colspan="6" class="empty">Nessun errore</td></tr>'; return; }
      body.innerHTML = logs.map(function(l) {
        return '<tr>' +
          '<td style="font-size:11px;color:#666">' + l.created_at + '</td>' +
          '<td style="font-size:12px">' + esc(l.device_model || '—') + '</td>' +
          '<td style="font-size:12px">' + esc(l.os_type || '') + ' ' + esc(l.os_version || '') + '</td>' +
          '<td style="font-size:12px">' + esc(l.app_version || '—') + '</td>' +
          '<td style="font-size:12px;color:#ff9800">' + esc(l.error_type || '—') + '</td>' +
          '<td class="err-msg" title="' + esc(l.error_message) + '">' + esc(l.error_message || '—') + '</td>' +
          '</tr>';
      }).join('');
    });
}

function esc(s){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
</script>
</body>
</html>`

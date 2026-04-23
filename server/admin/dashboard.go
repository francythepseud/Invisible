package main

const dashboardHTML = `<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Invisible — Admin</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#080810;--surface:#0f0f1a;--surface2:#161626;--border:#1e1e32;
  --purple:#7c3aed;--purple2:#4f2085;--blue:#2563eb;--teal:#0d9488;
  --text:#e2e8f0;--text2:#94a3b8;--text3:#4b5563;
  --green:#22c55e;--red:#ef4444;--orange:#f97316;--yellow:#eab308;
  --radius:12px;--sidebar:220px;
}
html,body{height:100%;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;background:var(--bg);color:var(--text)}
a{color:inherit;text-decoration:none}
button{cursor:pointer;font-family:inherit}

/* ── Login ─────────────────────────────────────────────────────────── */
#loginPage{display:flex;align-items:center;justify-content:center;min-height:100vh;background:radial-gradient(ellipse at 50% 0%,rgba(124,58,237,.12) 0%,transparent 70%)}
.login-card{background:var(--surface);border:1px solid var(--border);border-radius:20px;padding:44px 40px;width:380px;text-align:center}
.login-logo{width:52px;height:52px;background:linear-gradient(135deg,var(--purple),var(--purple2));border-radius:14px;display:inline-flex;align-items:center;justify-content:center;margin-bottom:20px}
.login-logo svg{width:26px;height:26px;fill:#fff}
.login-card h1{font-size:22px;font-weight:700;margin-bottom:6px}
.login-card p{font-size:13px;color:var(--text2);margin-bottom:28px}
.field{position:relative;margin-bottom:14px}
.field input{width:100%;padding:13px 16px;background:var(--surface2);border:1px solid var(--border);border-radius:10px;color:var(--text);font-size:14px;outline:none;transition:.15s}
.field input:focus{border-color:var(--purple)}
.btn-primary{width:100%;padding:13px;background:linear-gradient(135deg,var(--purple),var(--purple2));border:none;border-radius:10px;color:#fff;font-size:14px;font-weight:600;transition:.15s}
.btn-primary:hover{opacity:.9}
.login-err{font-size:12px;color:var(--red);margin-top:10px;min-height:16px}

/* ── Layout ─────────────────────────────────────────────────────────── */
#appPage{display:none;height:100vh;overflow:hidden}
.layout{display:flex;height:100%}

/* ── Sidebar ─────────────────────────────────────────────────────────── */
.sidebar{width:var(--sidebar);background:var(--surface);border-right:1px solid var(--border);display:flex;flex-direction:column;flex-shrink:0;overflow:hidden}
.sidebar-header{padding:22px 18px 16px;border-bottom:1px solid var(--border)}
.sidebar-logo{display:flex;align-items:center;gap:10px}
.sidebar-logo .ico{width:34px;height:34px;background:linear-gradient(135deg,var(--purple),var(--purple2));border-radius:9px;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.sidebar-logo .ico svg{width:18px;height:18px;fill:#fff}
.sidebar-logo span{font-size:15px;font-weight:700;letter-spacing:.3px}
.sidebar-logo small{display:block;font-size:10px;color:var(--text3);font-weight:400}
.sidebar-nav{flex:1;padding:12px 8px;overflow-y:auto}
.nav-section{font-size:10px;font-weight:600;color:var(--text3);letter-spacing:.8px;padding:14px 10px 6px;text-transform:uppercase}
.nav-item{display:flex;align-items:center;gap:10px;padding:9px 10px;border-radius:8px;font-size:13px;font-weight:500;color:var(--text2);cursor:pointer;transition:.15s;user-select:none}
.nav-item:hover{background:var(--surface2);color:var(--text)}
.nav-item.active{background:rgba(124,58,237,.15);color:var(--purple)}
.nav-item .ni{width:16px;height:16px;flex-shrink:0}
.nav-badge{margin-left:auto;background:var(--red);color:#fff;font-size:10px;font-weight:700;padding:2px 6px;border-radius:20px;min-width:18px;text-align:center}
.sidebar-footer{padding:12px 8px;border-top:1px solid var(--border)}
.sidebar-user{display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:8px}
.sidebar-user .avatar{width:28px;height:28px;background:linear-gradient(135deg,var(--purple),var(--blue));border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;color:#fff;flex-shrink:0}
.sidebar-user .info{flex:1;overflow:hidden}
.sidebar-user .name{font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sidebar-user .role{font-size:10px;color:var(--text3)}
.btn-logout{padding:5px 8px;background:transparent;border:1px solid var(--border);border-radius:6px;color:var(--text3);font-size:11px;transition:.15s}
.btn-logout:hover{border-color:var(--red);color:var(--red)}

/* ── Main ─────────────────────────────────────────────────────────── */
.main{flex:1;overflow-y:auto;display:flex;flex-direction:column}
.topbar{padding:16px 24px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;background:var(--surface);flex-shrink:0}
.topbar-title{font-size:16px;font-weight:700}
.topbar-right{display:flex;align-items:center;gap:12px}
.topbar-status{display:flex;align-items:center;gap:6px;font-size:12px;color:var(--text2)}
.dot{width:7px;height:7px;border-radius:50%}
.dot-green{background:var(--green);box-shadow:0 0 6px var(--green)}
.dot-red{background:var(--red)}
.dot-yellow{background:var(--yellow)}
.content{flex:1;padding:24px}

/* ── Sections ─────────────────────────────────────────────────────────── */
.section{display:none}
.section.active{display:block}

/* ── Stat cards ─────────────────────────────────────────────────────────── */
.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:22px}
.stat-card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:18px;position:relative;overflow:hidden}
.stat-card::before{content:'';position:absolute;top:0;right:0;width:60px;height:60px;border-radius:0 0 0 60px;opacity:.12}
.stat-card.purple::before{background:var(--purple)}
.stat-card.blue::before{background:var(--blue)}
.stat-card.green::before{background:var(--green)}
.stat-card.teal::before{background:var(--teal)}
.stat-icon{width:36px;height:36px;border-radius:9px;display:flex;align-items:center;justify-content:center;margin-bottom:14px}
.stat-icon svg{width:18px;height:18px}
.stat-card.purple .stat-icon{background:rgba(124,58,237,.18);color:var(--purple)}
.stat-card.blue .stat-icon{background:rgba(37,99,235,.18);color:var(--blue)}
.stat-card.green .stat-icon{background:rgba(34,197,94,.18);color:var(--green)}
.stat-card.teal .stat-icon{background:rgba(13,148,136,.18);color:var(--teal)}
.stat-n{font-size:30px;font-weight:800;line-height:1;margin-bottom:4px}
.stat-l{font-size:12px;color:var(--text2)}
.stat-trend{font-size:11px;color:var(--text3);margin-top:6px}

/* ── Cards ─────────────────────────────────────────────────────────── */
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden;margin-bottom:16px}
.card-header{padding:16px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between}
.card-title{font-size:14px;font-weight:600}
.card-body{padding:20px}

/* ── Form ─────────────────────────────────────────────────────────── */
.add-grid{display:grid;grid-template-columns:1fr 1.5fr 1fr auto;gap:10px;align-items:end}
.form-group label{display:block;font-size:11px;font-weight:600;color:var(--text2);margin-bottom:6px;letter-spacing:.3px;text-transform:uppercase}
.form-group input,.form-group select{width:100%;padding:10px 13px;background:var(--surface2);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:13px;outline:none;transition:.15s}
.form-group input:focus,.form-group select:focus{border-color:var(--purple)}
.form-group select option{background:var(--surface2)}
.form-err{font-size:11px;color:var(--red);margin-top:8px;min-height:14px}
.btn{padding:9px 16px;border:none;border-radius:8px;font-size:13px;font-weight:600;transition:.15s;display:inline-flex;align-items:center;gap:6px}
.btn svg{width:14px;height:14px}
.btn-add{background:linear-gradient(135deg,var(--purple),var(--purple2));color:#fff}
.btn-add:hover{opacity:.85}
.btn-sm{padding:5px 11px;border-radius:6px;font-size:11px;font-weight:600}
.btn-danger{background:rgba(239,68,68,.12);color:var(--red);border:1px solid rgba(239,68,68,.25)}
.btn-danger:hover{background:rgba(239,68,68,.2)}
.btn-success{background:rgba(34,197,94,.12);color:var(--green);border:1px solid rgba(34,197,94,.25)}
.btn-success:hover{background:rgba(34,197,94,.2)}
.btn-gray{background:rgba(255,255,255,.06);color:var(--text2);border:1px solid var(--border)}
.btn-gray:hover{background:rgba(255,255,255,.1)}
.btn-icon{padding:5px;background:transparent;border:1px solid transparent;border-radius:6px;color:var(--text3);display:inline-flex;align-items:center;justify-content:center;transition:.15s}
.btn-icon:hover{background:var(--surface2);border-color:var(--border);color:var(--text)}
.btn-icon svg{width:14px;height:14px}

/* ── Search bar ─────────────────────────────────────────────────────────── */
.search-bar{position:relative}
.search-bar svg{position:absolute;left:10px;top:50%;transform:translateY(-50%);width:14px;height:14px;color:var(--text3)}
.search-bar input{padding:8px 12px 8px 32px;background:var(--surface2);border:1px solid var(--border);border-radius:8px;color:var(--text);font-size:13px;outline:none;width:220px;transition:.15s}
.search-bar input:focus{border-color:var(--purple);width:260px}

/* ── Table ─────────────────────────────────────────────────────────── */
.table-wrap{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:13px}
thead th{padding:10px 14px;color:var(--text3);font-size:11px;font-weight:600;letter-spacing:.5px;text-transform:uppercase;text-align:left;border-bottom:1px solid var(--border);white-space:nowrap}
tbody td{padding:11px 14px;border-bottom:1px solid rgba(30,30,50,.5);vertical-align:middle}
tbody tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(255,255,255,.02)}
.empty-state{text-align:center;padding:50px 20px;color:var(--text3)}
.empty-state svg{width:36px;height:36px;margin-bottom:12px;opacity:.4}
.empty-state p{font-size:13px}

/* ── Badges ─────────────────────────────────────────────────────────── */
.badge{display:inline-flex;align-items:center;gap:4px;padding:3px 9px;border-radius:20px;font-size:11px;font-weight:600;white-space:nowrap}
.badge-active{background:rgba(34,197,94,.12);color:var(--green);border:1px solid rgba(34,197,94,.2)}
.badge-inactive{background:rgba(75,85,99,.15);color:#6b7280;border:1px solid rgba(75,85,99,.2)}
.badge-gdpr{background:rgba(37,99,235,.12);color:var(--blue);border:1px solid rgba(37,99,235,.2)}
.badge-warning{background:rgba(249,115,22,.12);color:var(--orange);border:1px solid rgba(249,115,22,.2)}

/* ── Hash ─────────────────────────────────────────────────────────── */
.hash-cell{display:flex;align-items:center;gap:6px}
.hash{font-family:'SF Mono',Menlo,monospace;font-size:11px;color:var(--text3)}
.online-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.actions-cell{display:flex;align-items:center;gap:4px}

/* ── Expiry inline edit ─────────────────────────────────────────────── */
.expiry-edit{display:none;align-items:center;gap:6px}
.expiry-edit input{padding:4px 8px;background:var(--surface2);border:1px solid var(--border);border-radius:6px;color:var(--text);font-size:11px;outline:none;width:120px}
.expiry-edit input:focus{border-color:var(--purple)}

/* ── Error modal ─────────────────────────────────────────────────────────── */
.modal-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:1000;align-items:center;justify-content:center}
.modal-overlay.open{display:flex}
.modal{background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:28px;max-width:680px;width:90%;max-height:80vh;overflow-y:auto}
.modal-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}
.modal-title{font-size:15px;font-weight:700}
.modal-close{background:transparent;border:none;color:var(--text2);padding:4px;border-radius:6px;display:flex;transition:.15s}
.modal-close:hover{color:var(--text);background:var(--surface2)}
.modal-close svg{width:18px;height:18px}
.stack-trace{background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:14px;font-family:monospace;font-size:11px;color:#94a3b8;white-space:pre-wrap;word-break:break-all;max-height:360px;overflow-y:auto}
.meta-row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}
.meta-tag{background:var(--surface2);border:1px solid var(--border);border-radius:6px;padding:4px 10px;font-size:11px;color:var(--text2)}
.meta-tag strong{color:var(--text)}

/* ── Toast ─────────────────────────────────────────────────────────── */
.toast{position:fixed;bottom:24px;right:24px;background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:12px 18px;font-size:13px;font-weight:500;z-index:2000;transform:translateY(16px);opacity:0;transition:.25s;pointer-events:none;max-width:320px}
.toast.show{transform:none;opacity:1}
.toast.success{border-color:rgba(34,197,94,.4);color:var(--green)}
.toast.error{border-color:rgba(239,68,68,.4);color:var(--red)}

/* ── Responsive ─────────────────────────────────────────────────────────── */
@media(max-width:900px){
  .stats-grid{grid-template-columns:repeat(2,1fr)}
  .add-grid{grid-template-columns:1fr 1fr}
  .sidebar{width:56px}
  .sidebar .sidebar-logo span,.sidebar .sidebar-logo small,.sidebar .nav-item span,.sidebar .sidebar-user .info,.sidebar .nav-section,.sidebar .btn-logout{display:none}
  .sidebar .nav-item{justify-content:center;padding:10px}
  .sidebar .nav-item .ni{width:18px;height:18px}
  .sidebar-user{justify-content:center}
}
@media(max-width:600px){
  .stats-grid{grid-template-columns:1fr 1fr}
  .add-grid{grid-template-columns:1fr}
  .search-bar input{width:160px}
}
</style>
</head>
<body>

<!-- ── Login ── -->
<div id="loginPage">
  <div class="login-card">
    <div class="login-logo">
      <svg viewBox="0 0 24 24"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 4.18L19 8.3V11c0 4.52-3.12 8.75-7 9.93C8.12 19.75 5 15.52 5 11V8.3L12 5.18z"/></svg>
    </div>
    <h1>Invisible Admin</h1>
    <p>Pannello di controllo sicuro</p>
    <div class="field">
      <input type="password" id="tokenInput" placeholder="Admin token" autocomplete="off" onkeydown="if(event.key==='Enter')doLogin()">
    </div>
    <button type="button" class="btn-primary" onclick="doLogin()">Accedi</button>
    <div class="login-err" id="loginErr"></div>
  </div>
</div>

<!-- ── App ── -->
<div id="appPage">
  <div class="layout">

    <!-- Sidebar -->
    <nav class="sidebar">
      <div class="sidebar-header">
        <div class="sidebar-logo">
          <div class="ico">
            <svg viewBox="0 0 24 24"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z"/></svg>
          </div>
          <div>
            <span>Invisible</span>
            <small>Admin Panel</small>
          </div>
        </div>
      </div>
      <div class="sidebar-nav">
        <div class="nav-section">Generale</div>
        <div class="nav-item active" onclick="showSection('dashboard')" id="nav-dashboard">
          <svg class="ni" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
          <span>Dashboard</span>
        </div>
        <div class="nav-section">Gestione</div>
        <div class="nav-item" onclick="showSection('users')" id="nav-users">
          <svg class="ni" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87"/><path d="M16 3.13a4 4 0 010 7.75"/></svg>
          <span>Utenti</span>
        </div>
        <div class="nav-item" onclick="showSection('errors')" id="nav-errors">
          <svg class="ni" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
          <span>Errori App</span>
          <span class="nav-badge" id="errBadge" style="display:none">0</span>
        </div>
      </div>
      <div class="sidebar-footer">
        <div class="sidebar-user">
          <div class="avatar">A</div>
          <div class="info">
            <div class="name">Admin</div>
            <div class="role">Superuser</div>
          </div>
          <button class="btn-logout" onclick="logout()" title="Esci">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
          </button>
        </div>
      </div>
    </nav>

    <!-- Main -->
    <div class="main">
      <div class="topbar">
        <div class="topbar-title" id="pageTitle">Dashboard</div>
        <div class="topbar-right">
          <div class="topbar-status" id="relayStatus">
            <div class="dot dot-yellow"></div>
            Verifica stato...
          </div>
          <button class="btn btn-gray btn-sm" onclick="refresh()">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
            Aggiorna
          </button>
        </div>
      </div>

      <div class="content">

        <!-- ── Dashboard section ── -->
        <div class="section active" id="sec-dashboard">
          <div class="stats-grid">
            <div class="stat-card purple">
              <div class="stat-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 00-3-3.87"/><path d="M16 3.13a4 4 0 010 7.75"/></svg></div>
              <div class="stat-n" id="s-total">—</div>
              <div class="stat-l">Utenti totali</div>
            </div>
            <div class="stat-card green">
              <div class="stat-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg></div>
              <div class="stat-n" id="s-active">—</div>
              <div class="stat-l">Account attivi</div>
            </div>
            <div class="stat-card teal">
              <div class="stat-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg></div>
              <div class="stat-n" id="s-online">—</div>
              <div class="stat-l">Online ora</div>
            </div>
            <div class="stat-card blue">
              <div class="stat-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></div>
              <div class="stat-n" id="s-gdpr">—</div>
              <div class="stat-l">GDPR accettato</div>
            </div>
          </div>

          <!-- Recent users -->
          <div class="card">
            <div class="card-header">
              <div class="card-title">Utenti recenti</div>
              <button class="btn btn-gray btn-sm" onclick="showSection('users')">Vedi tutti</button>
            </div>
            <div class="table-wrap">
              <table>
                <thead><tr><th>Nome</th><th>Hash</th><th>Online</th><th>Stato</th><th>Attivato</th></tr></thead>
                <tbody id="recentBody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- ── Users section ── -->
        <div class="section" id="sec-users">
          <div class="card">
            <div class="card-header">
              <div class="card-title">Aggiungi utente</div>
            </div>
            <div class="card-body">
              <div class="add-grid">
                <div class="form-group">
                  <label>Nome</label>
                  <input type="text" id="newName" placeholder="Es. Mario Rossi" onkeydown="if(event.key==='Enter')addUser()">
                </div>
                <div class="form-group">
                  <label>Identity Hash</label>
                  <input type="text" id="newHash" placeholder="64 caratteri hex" onkeydown="if(event.key==='Enter')addUser()">
                </div>
                <div class="form-group">
                  <label>Note (opz.)</label>
                  <input type="text" id="newNotes" placeholder="Azienda, ruolo..." onkeydown="if(event.key==='Enter')addUser()">
                </div>
                <div class="form-group">
                  <label>&nbsp;</label>
                  <button type="button" class="btn btn-add" onclick="addUser()">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                    Aggiungi
                  </button>
                </div>
              </div>
              <div class="form-err" id="addErr"></div>
            </div>
          </div>

          <div class="card">
            <div class="card-header">
              <div class="card-title">Utenti autorizzati</div>
              <div class="search-bar">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <input type="text" id="userSearch" placeholder="Cerca nome o hash..." oninput="filterUsers()">
              </div>
            </div>
            <div class="table-wrap">
              <table>
                <thead><tr><th>Nome</th><th>Identity Hash</th><th>Online</th><th>Stato</th><th>GDPR</th><th>Scadenza</th><th>Azioni</th></tr></thead>
                <tbody id="usersBody"></tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- ── Errors section ── -->
        <div class="section" id="sec-errors">
          <div class="card">
            <div class="card-header">
              <div class="card-title">Log errori app</div>
              <div style="display:flex;gap:8px">
                <button class="btn btn-gray btn-sm" onclick="loadErrors()">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
                  Aggiorna
                </button>
                <button class="btn btn-danger btn-sm" onclick="clearErrors()">
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>
                  Cancella tutti
                </button>
              </div>
            </div>
            <div class="table-wrap">
              <table>
                <thead><tr><th>Data</th><th>Dispositivo</th><th>OS</th><th>Versione</th><th>Tipo errore</th><th>Messaggio</th><th></th></tr></thead>
                <tbody id="errorsBody"></tbody>
              </table>
            </div>
          </div>
        </div>

      </div><!-- /content -->
    </div><!-- /main -->
  </div><!-- /layout -->
</div><!-- /appPage -->

<!-- Error detail modal -->
<div class="modal-overlay" id="errorModal" onclick="if(event.target===this)closeModal()">
  <div class="modal">
    <div class="modal-header">
      <div class="modal-title" id="modalTitle">Dettaglio errore</div>
      <button class="modal-close" onclick="closeModal()"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>
    <div class="meta-row" id="modalMeta"></div>
    <div style="font-size:12px;color:var(--text2);margin-bottom:8px">Stack trace:</div>
    <div class="stack-trace" id="modalStack"></div>
  </div>
</div>

<!-- Toast -->
<div class="toast" id="toast"></div>

<script>
let TOKEN = sessionStorage.getItem('admin_token') || '';
let _allUsers = [];
let _refreshTimer = null;

// ── Auth ──────────────────────────────────────────────────────────
if (TOKEN) {
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => {
      if (r.ok) showApp();
      else { sessionStorage.removeItem('admin_token'); TOKEN = ''; }
    }).catch(() => {});
}

function doLogin() {
  const t = document.getElementById('tokenInput').value.trim();
  if (!t) return;
  TOKEN = t;
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => {
      if (r.status === 401) { document.getElementById('loginErr').textContent = 'Token non valido'; TOKEN = ''; return; }
      sessionStorage.setItem('admin_token', TOKEN);
      showApp();
    }).catch(() => { document.getElementById('loginErr').textContent = 'Errore di connessione'; });
}

function showApp() {
  document.getElementById('loginPage').style.display = 'none';
  document.getElementById('appPage').style.display = 'block';
  loadDashboard();
  startAutoRefresh();
}

function logout() {
  sessionStorage.removeItem('admin_token');
  TOKEN = '';
  stopAutoRefresh();
  document.getElementById('appPage').style.display = 'none';
  document.getElementById('loginPage').style.display = 'flex';
  document.getElementById('tokenInput').value = '';
}

// ── Navigation ──────────────────────────────────────────────────
const SECTIONS = ['dashboard','users','errors'];
const TITLES = {dashboard:'Dashboard',users:'Gestione Utenti',errors:'Log Errori App'};

function showSection(name) {
  SECTIONS.forEach(s => {
    document.getElementById('sec-'+s).classList.toggle('active', s===name);
    document.getElementById('nav-'+s).classList.toggle('active', s===name);
  });
  document.getElementById('pageTitle').textContent = TITLES[name] || name;
  if (name === 'users') loadUsers();
  if (name === 'errors') loadErrors();
}

function refresh() {
  const active = SECTIONS.find(s => document.getElementById('sec-'+s).classList.contains('active')) || 'dashboard';
  if (active === 'dashboard') loadDashboard();
  else if (active === 'users') loadUsers();
  else if (active === 'errors') loadErrors();
  checkRelayStatus();
}

// ── Auto-refresh ──────────────────────────────────────────────────
function startAutoRefresh() {
  stopAutoRefresh();
  _refreshTimer = setInterval(() => { if (TOKEN) refresh(); }, 30000);
  checkRelayStatus();
}
function stopAutoRefresh() {
  if (_refreshTimer) clearInterval(_refreshTimer);
  _refreshTimer = null;
}

// ── Relay status check ──────────────────────────────────────────
function checkRelayStatus() {
  fetch('/healthz').then(r => {
    const el = document.getElementById('relayStatus');
    el.innerHTML = r.ok
      ? '<div class="dot dot-green"></div> Sistema operativo'
      : '<div class="dot dot-red"></div> Errore server';
  }).catch(() => {
    document.getElementById('relayStatus').innerHTML = '<div class="dot dot-red"></div> Non raggiungibile';
  });
}

// ── Dashboard ──────────────────────────────────────────────────
function loadDashboard() {
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(users => {
      _allUsers = users;
      document.getElementById('s-total').textContent = users.length;
      document.getElementById('s-active').textContent = users.filter(u=>u.enabled).length;
      document.getElementById('s-online').textContent = users.filter(u=>u.online).length;
      document.getElementById('s-gdpr').textContent = users.filter(u=>u.gdpr_accepted).length;
      const body = document.getElementById('recentBody');
      const recent = users.slice(0, 6);
      if (!recent.length) {
        body.innerHTML = '<tr><td colspan="5" class="empty-state"><p>Nessun utente</p></td></tr>';
        return;
      }
      body.innerHTML = recent.map(u => renderUserRow(u, true)).join('');
    });
  // Load errors count for badge
  fetch('/admin/api/errors', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(logs => {
      const today = new Date().toISOString().substring(0,10);
      const todayCount = logs.filter(l => l.created_at && l.created_at.startsWith(today)).length;
      const badge = document.getElementById('errBadge');
      if (todayCount > 0) { badge.textContent = todayCount; badge.style.display = ''; }
      else badge.style.display = 'none';
    }).catch(() => {});
}

// ── Users ──────────────────────────────────────────────────
function loadUsers() {
  fetch('/admin/api/users', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(users => {
      _allUsers = users;
      renderUsers(users);
    });
}

function filterUsers() {
  const q = document.getElementById('userSearch').value.toLowerCase().trim();
  if (!q) { renderUsers(_allUsers); return; }
  renderUsers(_allUsers.filter(u =>
    u.name.toLowerCase().includes(q) ||
    u.identity_hash.toLowerCase().includes(q) ||
    (u.notes && u.notes.toLowerCase().includes(q))
  ));
}

function renderUsers(users) {
  const body = document.getElementById('usersBody');
  if (!users.length) {
    body.innerHTML = '<tr><td colspan="7" class="empty-state"><p>Nessun utente trovato</p></td></tr>';
    return;
  }
  body.innerHTML = users.map(u => renderUserRow(u, false)).join('');
}

function renderUserRow(u, compact) {
  const onlineDot = u.online
    ? '<div class="online-dot" style="background:var(--green);box-shadow:0 0 5px var(--green)" title="Online ora"></div>'
    : '<div class="online-dot" style="background:var(--surface2);border:1px solid var(--border)" title="' + (u.last_seen_at ? 'Ultimo accesso: '+u.last_seen_at : 'Mai connesso') + '"></div>';

  const statusBadge = u.enabled
    ? '<span class="badge badge-active">Attivo</span>'
    : '<span class="badge badge-inactive">Disattivo</span>';

  if (compact) {
    return '<tr>' +
      '<td><strong>' + esc(u.name) + '</strong>' + (u.notes ? '<br><small style="color:var(--text3)">' + esc(u.notes) + '</small>' : '') + '</td>' +
      '<td><span class="hash">' + u.identity_hash.substring(0,12) + '...</span></td>' +
      '<td>' + onlineDot + '</td>' +
      '<td>' + statusBadge + '</td>' +
      '<td style="font-size:12px;color:var(--text3)">' + (u.enabled_at || '—') + '</td>' +
      '</tr>';
  }

  let expiryCell = '<span style="color:var(--text3);font-size:12px">—</span>';
  if (u.expires_at) {
    const daysLeft = Math.ceil((new Date(u.expires_at) - new Date()) / 86400000);
    const color = daysLeft < 30 ? 'var(--orange)' : 'var(--text2)';
    const warn = daysLeft < 30 ? ' <span class="badge badge-warning">'+daysLeft+'gg</span>' : '';
    expiryCell = '<span style="color:'+color+';font-size:12px">'+u.expires_at+'</span>'+warn;
  }

  const gdprCell = u.gdpr_accepted
    ? '<span class="badge badge-gdpr">GDPR</span>'
    : '<span style="color:var(--text3);font-size:11px">—</span>';

  return '<tr id="row-'+u.identity_hash.substring(0,8)+'">' +
    '<td><strong>' + esc(u.name) + '</strong>' + (u.notes ? '<br><small style="color:var(--text3)">' + esc(u.notes) + '</small>' : '') + '</td>' +
    '<td><div class="hash-cell"><span class="hash">' + u.identity_hash.substring(0,16) + '...</span>' +
      '<button class="btn-icon" onclick="copyHash(\''+u.identity_hash+'\')" title="Copia hash completo"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg></button>' +
    '</div></td>' +
    '<td>' + onlineDot + '</td>' +
    '<td>' + statusBadge + '</td>' +
    '<td>' + gdprCell + '</td>' +
    '<td>' + expiryCell + '</td>' +
    '<td><div class="actions-cell">' +
      '<button type="button" class="btn btn-sm '+(u.enabled?'btn-danger':'btn-success')+'" onclick="toggleUser(\''+u.identity_hash+'\')">'+(u.enabled?'Disattiva':'Attiva')+'</button>' +
      '<button type="button" class="btn btn-sm btn-danger" onclick="deleteUser(\''+u.identity_hash+'\',\''+esc(u.name)+'\')">Elimina</button>' +
    '</div></td>' +
    '</tr>';
}

function addUser() {
  const name = document.getElementById('newName').value.trim();
  const hash = document.getElementById('newHash').value.trim();
  const notes = document.getElementById('newNotes').value.trim();
  const err = document.getElementById('addErr');
  if (!name || !hash) { err.textContent = 'Nome e hash sono obbligatori'; return; }
  if (hash.length < 16) { err.textContent = 'Identity hash non valido (troppo corto)'; return; }
  err.textContent = '';
  fetch('/admin/api/users', {
    method:'POST',
    headers:{'X-Admin-Token':TOKEN,'Content-Type':'application/json'},
    body: JSON.stringify({identity_hash:hash, name, notes})
  }).then(r => {
    if (!r.ok) { err.textContent = 'Errore durante l\'aggiunta'; return; }
    document.getElementById('newName').value = '';
    document.getElementById('newHash').value = '';
    document.getElementById('newNotes').value = '';
    showToast('Utente aggiunto', 'success');
    loadUsers(); loadDashboard();
  }).catch(() => { err.textContent = 'Errore di rete'; });
}

function toggleUser(hash) {
  fetch('/admin/api/users/toggle?hash='+encodeURIComponent(hash), {method:'POST',headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(d => {
      showToast(d.enabled ? 'Utente attivato' : 'Utente disattivato', d.enabled ? 'success' : 'error');
      loadUsers(); loadDashboard();
    });
}

function deleteUser(hash, name) {
  if (!confirm('Eliminare "'+name+'"?\nL\'utente non potrà più accedere all\'app.')) return;
  fetch('/admin/api/users/delete?hash='+encodeURIComponent(hash), {method:'DELETE',headers:{'X-Admin-Token':TOKEN}})
    .then(() => { showToast('Utente eliminato', 'error'); loadUsers(); loadDashboard(); });
}

function copyHash(hash) {
  navigator.clipboard.writeText(hash).then(() => showToast('Hash copiato negli appunti', 'success'));
}

// ── Errors ──────────────────────────────────────────────────
function loadErrors() {
  fetch('/admin/api/errors', {headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(logs => {
      const body = document.getElementById('errorsBody');
      if (!logs.length) {
        body.innerHTML = '<tr><td colspan="7" class="empty-state"><p>Nessun errore registrato</p></td></tr>';
        return;
      }
      body.innerHTML = logs.map(function(l) {
        const hasStack = l.stack_trace && l.stack_trace.length > 2;
        return '<tr>' +
          '<td style="font-size:11px;color:var(--text3);white-space:nowrap">' + esc(l.created_at) + '</td>' +
          '<td style="font-size:12px">' + esc(l.device_model || '—') + '</td>' +
          '<td style="font-size:12px">' + esc((l.os_type||'') + ' ' + (l.os_version||'')).trim() + '</td>' +
          '<td style="font-size:12px">' + esc(l.app_version || '—') + '</td>' +
          '<td><span class="badge badge-warning">' + esc(l.error_type || '—') + '</span></td>' +
          '<td style="max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;color:var(--text2)" title="'+esc(l.error_message||'')+'">'+esc(l.error_message||'—')+'</td>' +
          '<td>' + (hasStack ? '<button class="btn btn-sm btn-gray" onclick="showError('+l.id+')">Stack</button>' : '') + '</td>' +
          '</tr>';
      }).join('');
      _errorsCache = logs;
    });
}

let _errorsCache = [];
function showError(id) {
  const l = _errorsCache.find(e => e.id === id);
  if (!l) return;
  document.getElementById('modalTitle').textContent = esc(l.error_type || 'Errore sconosciuto');
  document.getElementById('modalMeta').innerHTML =
    '<div class="meta-tag"><strong>Data:</strong> ' + esc(l.created_at) + '</div>' +
    '<div class="meta-tag"><strong>Dispositivo:</strong> ' + esc(l.device_model||'—') + '</div>' +
    '<div class="meta-tag"><strong>OS:</strong> ' + esc((l.os_type||'') + ' ' + (l.os_version||'')) + '</div>' +
    '<div class="meta-tag"><strong>App:</strong> ' + esc(l.app_version||'—') + '</div>' +
    (l.identity_hash ? '<div class="meta-tag"><strong>Hash:</strong> ' + esc(l.identity_hash.substring(0,12)) + '...</div>' : '');
  document.getElementById('modalStack').textContent = l.stack_trace || l.error_message || '—';
  document.getElementById('errorModal').classList.add('open');
}
function closeModal() {
  document.getElementById('errorModal').classList.remove('open');
}

function clearErrors() {
  if (!confirm('Cancellare definitivamente tutti i log errori?')) return;
  fetch('/admin/api/errors', {method:'DELETE', headers:{'X-Admin-Token':TOKEN}})
    .then(r => r.json())
    .then(d => {
      showToast('Cancellati ' + (d.deleted||0) + ' log errori', 'success');
      loadErrors();
      document.getElementById('errBadge').style.display = 'none';
    }).catch(() => showToast('Errore durante la cancellazione', 'error'));
}

// ── Toast ──────────────────────────────────────────────────
let _toastTimer = null;
function showToast(msg, type) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = 'toast show ' + (type||'');
  if (_toastTimer) clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => { el.classList.remove('show'); }, 2800);
}

// ── Escape ──────────────────────────────────────────────────
function esc(s) {
  return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
</script>
</body>
</html>`

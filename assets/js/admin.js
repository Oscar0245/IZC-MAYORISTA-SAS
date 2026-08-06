/* Perfil del administrador: datos de sesión + panel de clientes */
(function () {
  'use strict';

  var API_ORIGIN = 'http://127.0.0.1:8080';
  var activeTab = 'users';
  var quotesCache = [];

  function setMessage(elId, text, type) {
    var el = document.getElementById(elId);
    if (!el) return;
    el.textContent = text || '';
    el.className = 'auth-message' + (type ? ' is-' + type : '');
  }

  function formatDate(value) {
    if (!value) return '—';
    var d = new Date(value);
    if (isNaN(d.getTime())) return String(value);
    return d.toLocaleString('es-CO', {
      year: 'numeric',
      month: 'short',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function formatCOP(value) {
    return '$ ' + Math.round(Number(value)).toLocaleString('es-CO') + ' COP';
  }

  function postAdminApi(payload) {
    var body = JSON.stringify(payload);
    var endpoints = [API_ORIGIN + '/api/auth', 'api/auth.php', 'api/auth'];

    function tryOne(i) {
      if (i >= endpoints.length) {
        return Promise.reject(new Error('sin api'));
      }
      return fetch(endpoints[i], {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body,
        cache: 'no-store'
      }).then(function (res) {
        return res.json().then(function (data) {
          if (!data || typeof data !== 'object') throw new Error('Respuesta inválida');
          return data;
        });
      }).catch(function () {
        return tryOne(i + 1);
      });
    }

    function run() {
      return tryOne(0);
    }

    if (window.IZCAuth && typeof window.IZCAuth.ensureLocalApi === 'function') {
      return window.IZCAuth.ensureLocalApi().then(run, run);
    }
    return run();
  }

  function setActiveTab(tab) {
    activeTab = tab;
    var usersPanel = document.getElementById('adminPanelUsers');
    var quotesPanel = document.getElementById('adminPanelQuotes');
    var trmPanel = document.getElementById('adminPanelTrm');
    var tabs = document.querySelectorAll('.admin-stat.is-tab');

    tabs.forEach(function (el) {
      el.classList.toggle('is-active', el.getAttribute('data-tab') === tab);
    });
    if (usersPanel) usersPanel.hidden = tab !== 'users';
    if (quotesPanel) quotesPanel.hidden = tab !== 'quotes';
    if (trmPanel) trmPanel.hidden = tab !== 'trm';

    if (tab === 'users') loadUsers();
    else if (tab === 'quotes') loadQuotes();
    else if (tab === 'trm') loadTrmPanel();
  }

  function renderQuotes(quotes) {
    var body = document.getElementById('adminQuotesBody');
    var count = document.getElementById('adminQuoteCount');
    quotesCache = quotes || [];
    if (count) count.textContent = String(quotesCache.length);
    if (!body) return;

    if (!quotesCache.length) {
      body.innerHTML = '<tr><td colspan="7" class="admin-empty">Aún no hay cotizaciones terminadas.</td></tr>';
      return;
    }

    body.innerHTML = quotesCache.map(function (q, idx) {
      var totals = q.totals || {};
      var itemCount = (q.items && q.items.length) || 0;
      var copIva = totals.copIva != null ? formatCOP(totals.copIva) : '—';
      return (
        '<tr>' +
          '<td class="admin-row-num">' + (idx + 1) + '</td>' +
          '<td>' + escapeHtml(formatDate(q.created_at)) + '</td>' +
          '<td>' + escapeHtml(q.nombre || '—') + '</td>' +
          '<td>' + escapeHtml(q.nit || '') + '</td>' +
          '<td>' + itemCount + '</td>' +
          '<td>' + escapeHtml(copIva) + '</td>' +
          '<td class="admin-actions">' +
            '<button type="button" class="admin-view-quote" data-idx="' + idx + '">Ver</button>' +
          '</td>' +
        '</tr>'
      );
    }).join('');
  }

  function fetchQuotes() {
    if (!window.IZCAuth || !IZCAuth.getSessionNit) {
      return Promise.resolve({ ok: false, quotes: [] });
    }
    return postAdminApi({
      action: 'list_quotes',
      admin_nit: IZCAuth.getSessionNit()
    });
  }

  function loadQuotes(options) {
    var silent = !!(options && options.silent);
    if (!silent) setMessage('adminMessage', 'Cargando cotizaciones…', '');

    return fetchQuotes().then(function (data) {
      if (!data.ok) {
        if (!silent) {
          setMessage('adminMessage', data.error || 'No se pudo cargar el historial.', 'error');
        }
        renderQuotes([]);
        return;
      }
      renderQuotes(data.quotes || []);
      if (!silent) setMessage('adminMessage', '', '');
    }).catch(function () {
      if (!silent) {
        setMessage('adminMessage', 'No se pudo cargar. Ejecuta tools\\ABRIR.bat.', 'error');
      }
      renderQuotes([]);
    });
  }

  function fetchTrm() {
    return postAdminApi({ action: 'get_trm' });
  }

  function updateTrmBadge(value) {
    var el = document.getElementById('adminTrmValue');
    if (el && value != null && isFinite(Number(value))) {
      el.textContent = String(Number(value));
    }
  }

  function loadTrmPanel() {
    return fetchTrm().then(function (data) {
      if (!data || !data.ok) return;
      var input = document.getElementById('adminTrmInput');
      var meta = document.getElementById('adminTrmMeta');
      if (input) input.value = data.value;
      updateTrmBadge(data.value);
      if (meta) {
        meta.textContent = data.updated_at
          ? 'Última actualización: ' + formatDate(data.updated_at) +
            (data.updated_by_nombre ? ' · ' + data.updated_by_nombre : '')
          : 'Aún no se ha actualizado la TRM del día.';
      }
    }).catch(function () { /* ignore */ });
  }

  function saveTrmAdmin() {
    var input = document.getElementById('adminTrmInput');
    var value = input ? Number(input.value) : 0;
    if (!isFinite(value) || value <= 0) {
      setMessage('adminMessage', 'Ingresa una TRM válida mayor que cero.', 'error');
      return;
    }
    setMessage('adminMessage', 'Guardando TRM…', '');
    postAdminApi({
      action: 'set_trm',
      admin_nit: IZCAuth.getSessionNit(),
      admin_nombre: IZCAuth.getSessionNombre ? IZCAuth.getSessionNombre() : '',
      value: value
    }).then(function (data) {
      if (!data || !data.ok) {
        var err = (data && data.error) || 'No se pudo guardar la TRM.';
        if (/acción no válida/i.test(err)) {
          err += ' Cierra y vuelve a abrir con tools\\ABRIR.bat (reinicia el servidor solo).';
        }
        setMessage('adminMessage', err, 'error');
        return;
      }
      updateTrmBadge(data.value);
      loadTrmPanel();
      setMessage('adminMessage', data.message || 'TRM actualizada.', 'ok');
    }).catch(function () {
      setMessage('adminMessage', 'No se pudo guardar. Abre tools\\ABRIR.bat para reiniciar el servidor.', 'error');
    });
  }

  function openQuoteDetail(idx) {
    var quote = quotesCache[idx];
    var modal = document.getElementById('quoteDetailModal');
    var meta = document.getElementById('quoteDetailMeta');
    var body = document.getElementById('quoteDetailBody');
    if (!quote || !modal || !body) return;

    if (meta) {
      meta.textContent =
        (quote.nombre || '—') + ' · NIT ' + (quote.nit || '') +
        ' · ' + formatDate(quote.created_at);
    }

    var rows = (quote.items || []).map(function (line) {
      return (
        '<tr>' +
          '<td>' + escapeHtml(line.sku || '') + '</td>' +
          '<td>' + escapeHtml(line.name || '—') + '</td>' +
          '<td>' + (line.qty || 0) + '</td>' +
          '<td>' + escapeHtml(formatCOP(line.totalCopIva != null ? line.totalCopIva : line.copIva)) + '</td>' +
        '</tr>'
      );
    }).join('');

    var totals = quote.totals || {};
    body.innerHTML =
      '<table class="admin-quote-detail-table">' +
        '<thead><tr><th>SKU</th><th>Producto</th><th>Cant.</th><th>Total COP + IVA</th></tr></thead>' +
        '<tbody>' + (rows || '<tr><td colspan="4">Sin productos</td></tr>') + '</tbody>' +
      '</table>' +
      '<p class="admin-quote-total"><strong>Total COP + IVA:</strong> ' +
        escapeHtml(formatCOP(totals.copIva)) + '</p>';

    modal.hidden = false;
  }

  function bindTabs() {
    document.querySelectorAll('.admin-stat.is-tab').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var tab = btn.getAttribute('data-tab') || 'users';
        setActiveTab(tab);
      });
    });

    var quotesBody = document.getElementById('adminQuotesBody');
    if (quotesBody) {
      quotesBody.addEventListener('click', function (e) {
        var btn = e.target.closest('.admin-view-quote');
        if (!btn) return;
        openQuoteDetail(Number(btn.getAttribute('data-idx')));
      });
    }

    var quoteModal = document.getElementById('quoteDetailModal');
    if (quoteModal) {
      quoteModal.addEventListener('click', function (e) {
        if (e.target.closest('[data-modal-close]')) quoteModal.hidden = true;
      });
    }

    var trmSave = document.getElementById('adminTrmSave');
    if (trmSave) trmSave.addEventListener('click', saveTrmAdmin);
  }

  function fillProfile() {
    var nit = (window.IZCAuth && IZCAuth.getSessionNit()) || '';
    var nombre = (window.IZCAuth && IZCAuth.getSessionNombre && IZCAuth.getSessionNombre()) || '';
    var input = document.getElementById('profileNit');
    var nombreInput = document.getElementById('profileNombre');
    var greet = document.getElementById('profileGreeting');

    if (!nit) {
      setMessage('adminMessage', 'Debes iniciar sesión como administrador.', 'error');
      if (input) input.value = '';
      if (nombreInput) nombreInput.value = '';
      if (greet) greet.textContent = 'Hola';
      window.setTimeout(function () {
        if (!(window.IZCAuth && IZCAuth.getSessionNit && IZCAuth.getSessionNit())) {
          window.location.href = 'login.html';
        }
      }, 800);
      return false;
    }

    if (!IZCAuth.isAdmin || !IZCAuth.isAdmin()) {
      window.location.replace('perfil.html');
      return false;
    }

    if (input) input.value = nit;
    if (nombreInput) {
      nombreInput.value = nombre || '—';
      nombreInput.readOnly = true;
    }
    if (greet) greet.textContent = 'Hola ' + (nombre || 'admin');
    setMessage('adminMessage', '', '');
    return true;
  }

  function renderUsers(users) {
    var body = document.getElementById('adminUsersBody');
    var count = document.getElementById('adminUserCount');
    if (count) count.textContent = String((users && users.length) || 0);
    if (!body) return;

    if (!users || !users.length) {
      body.innerHTML = '<tr><td colspan="5" class="admin-empty">No hay usuarios registrados.</td></tr>';
      return;
    }

    body.innerHTML = users.map(function (u, idx) {
      var nit = u.nit || '';
      var btn = '<button type="button" class="admin-delete" data-nit="' + escapeHtml(nit) + '">Eliminar</button>';
      return (
        '<tr>' +
          '<td class="admin-row-num">' + (idx + 1) + '</td>' +
          '<td>' + escapeHtml(u.nombre || '—') + '</td>' +
          '<td>' + escapeHtml(nit) + '</td>' +
          '<td>' + escapeHtml(formatDate(u.created_at)) + '</td>' +
          '<td class="admin-actions">' + btn + '</td>' +
        '</tr>'
      );
    }).join('');
  }

  function loadUsers() {
    if (!window.IZCAuth || !IZCAuth.listUsersForAdmin) return;
    setMessage('adminMessage', 'Cargando…', '');
    IZCAuth.listUsersForAdmin().then(function (data) {
      if (!data.ok) {
        setMessage('adminMessage', data.error || 'No se pudo cargar.', 'error');
        return;
      }
      var sourceEl = document.getElementById('adminSource');
      if (sourceEl) sourceEl.textContent = data.source || '—';
      // No mostrar al admin en la tabla; sí permanece en usuarios.json
      var users = (data.users || []).filter(function (u) {
        return !(IZCAuth.isAdminNit && IZCAuth.isAdminNit(u.nit));
      });
      renderUsers(users);
      setMessage('adminMessage', '', '');
    }).catch(function (err) {
      console.error(err);
      setMessage('adminMessage', 'Error al cargar usuarios.', 'error');
    });
  }

  function bindTable() {
    var body = document.getElementById('adminUsersBody');
    var modal = document.getElementById('deleteModal');
    var modalText = document.getElementById('deleteModalText');
    var confirmBtn = document.getElementById('deleteModalConfirm');
    var pendingNit = '';
    var pendingBtn = null;

    function closeModal() {
      if (modal) modal.hidden = true;
      pendingNit = '';
      pendingBtn = null;
    }

    function openModal(nit, btn) {
      pendingNit = nit;
      pendingBtn = btn;
      if (modalText) {
        modalText.textContent = '¿Quieres eliminar el cliente con NIT ' + nit + '?';
      }
      if (modal) modal.hidden = false;
      if (confirmBtn) confirmBtn.focus();
    }

    if (modal) {
      modal.addEventListener('click', function (e) {
        if (e.target.closest('[data-modal-close]')) closeModal();
      });
    }

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && modal && !modal.hidden) closeModal();
    });

    if (confirmBtn) {
      confirmBtn.addEventListener('click', function () {
        var nit = pendingNit;
        var btn = pendingBtn;
        closeModal();
        if (!nit || !window.IZCAuth) return;
        if (btn) btn.disabled = true;
        IZCAuth.deleteUserForAdmin(nit).then(function (data) {
          if (!data.ok) {
            setMessage('adminMessage', data.error || 'No se pudo eliminar.', 'error');
            if (btn) btn.disabled = false;
            return;
          }
          setMessage('adminMessage', data.message || 'Usuario eliminado.', 'ok');
          loadUsers();
        }).catch(function (err) {
          console.error(err);
          setMessage('adminMessage', 'Error al eliminar.', 'error');
          if (btn) btn.disabled = false;
        });
      });
    }

    if (!body) return;
    body.addEventListener('click', function (e) {
      var btn = e.target.closest('.admin-delete');
      if (!btn || !window.IZCAuth) return;
      var nit = btn.getAttribute('data-nit') || '';
      if (!nit) return;
      openModal(nit, btn);
    });
  }

  function bindLogout() {
    var btn = document.getElementById('profileLogout');
    if (!btn) return;
    btn.addEventListener('click', function () {
      if (window.IZCAuth && IZCAuth.logout) IZCAuth.logout();
      else window.location.href = 'index.html';
    });
  }

  function init() {
    bindLogout();
    bindTable();
    bindTabs();
    var refresh = document.getElementById('adminRefresh');
    if (refresh) refresh.addEventListener('click', function () {
      if (activeTab === 'quotes') loadQuotes();
      else {
        loadUsers();
        loadQuotes({ silent: true });
      }
    });
    document.addEventListener('izc:auth-changed', function () {
      if (fillProfile()) {
        setActiveTab(activeTab);
        loadQuotes({ silent: true });
        loadTrmPanel();
      }
    });

    var ready = (window.IZCAuth && IZCAuth.whenSessionReady)
      ? IZCAuth.whenSessionReady()
      : Promise.resolve();

    ready.then(function () {
      if (!fillProfile()) return;
      setActiveTab('users');
      loadQuotes({ silent: true });
      loadTrmPanel();
    }).catch(function () {
      if (!fillProfile()) return;
      setActiveTab('users');
      loadTrmPanel();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

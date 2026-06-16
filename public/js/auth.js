const Auth = {
  getToken: () => localStorage.getItem('session_token') || '',
  getUser: () => JSON.parse(localStorage.getItem('user_data') || '{}'),
  isLoggedIn: () => !!localStorage.getItem('session_token'),
  isAdmin: () => localStorage.getItem('is_admin') === 'true',
  getUserName: () => localStorage.getItem('user_name') || '',

  setSession(data) {
    // Server returns {token, user: {...}} — handle both flat and nested
    const u = data.user || data;
    localStorage.setItem('session_token', data.token || '');
    localStorage.setItem('user_name', u.name || '');
    localStorage.setItem('is_admin', (u.is_admin === 1 || u.is_admin === true) ? 'true' : 'false');
    localStorage.setItem('is_premium', u.access_type === 'premium' ? 'true' : 'false');
    localStorage.setItem('user_data', JSON.stringify(u));
  },

  logout() {
    localStorage.clear();
    window.location.href = '/auth.html';
  },

  headers() {
    return {
      'Authorization': `Bearer ${this.getToken()}`,
      'Content-Type': 'application/json',
    };
  },

  async api(path, options = {}) {
    const res = await fetch(CONFIG.workerUrl + path, {
      ...options,
      headers: { ...this.headers(), ...(options.headers || {}) },
    });
    return res;
  },
};

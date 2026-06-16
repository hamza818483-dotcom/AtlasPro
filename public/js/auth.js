const Auth = {
  getToken: () => localStorage.getItem('session_token') || '',
  getUser: () => JSON.parse(localStorage.getItem('user_data') || '{}'),
  isLoggedIn: () => !!localStorage.getItem('session_token'),
  isAdmin: () => localStorage.getItem('is_admin') === 'true',
  getUserName: () => localStorage.getItem('user_name') || '',

  setSession(data) {
    localStorage.setItem('session_token', data.token || '');
    localStorage.setItem('user_name', data.name || data.user_name || '');
    localStorage.setItem('is_admin', data.is_admin ? 'true' : 'false');
    localStorage.setItem('user_data', JSON.stringify(data));
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

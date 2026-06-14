import http from 'k6/http';
import { check, sleep } from 'k6';

// Smoke test — quick sanity check after deploy (low load).
//   make pf          # in another terminal
//   make loadtest-smoke

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    http_req_failed: ['rate==0'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const EMAIL = __ENV.ADMIN_EMAIL || 'admin@ccf.local';
const PASS = __ENV.ADMIN_PASSWORD || 'Admin12345!';

export function setup() {
  const login = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: PASS }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  check(login, { 'login status 200': (r) => r.status === 200 });
  const token = login.json('data.auth_token');
  if (!token) {
    throw new Error('login failed — check ADMIN_EMAIL / ADMIN_PASSWORD and that the API is reachable');
  }
  return { token };
}

export default function (data) {
  const auth = { Authorization: `Bearer ${data.token}` };

  check(http.get(`${BASE}/api/auth/publickey`), {
    'publickey ok': (r) => r.status === 200,
  });

  check(http.get(`${BASE}/api/admin/agents`, { headers: auth }), {
    'agents list ok': (r) => r.status === 200,
  });

  check(http.get(`${BASE}/swagger/index.html`), {
    'swagger ok': (r) => r.status === 200,
  });

  sleep(0.5);
}

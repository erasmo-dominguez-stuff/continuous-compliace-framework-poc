import http from 'k6/http';
import { check, sleep } from 'k6';

// Load test — sustained read traffic against authenticated API endpoints.
//   make pf          # in another terminal
//   make loadtest
//
// Override: BASE_URL, ADMIN_EMAIL, ADMIN_PASSWORD, K6_VUS, K6_DURATION

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const EMAIL = __ENV.ADMIN_EMAIL || 'admin@ccf.local';
const PASS = __ENV.ADMIN_PASSWORD || 'Admin12345!';

export const options = {
  stages: [
    { duration: __ENV.K6_RAMP || '30s', target: Number(__ENV.K6_VUS || 10) },
    { duration: __ENV.K6_DURATION || '2m', target: Number(__ENV.K6_VUS || 10) },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<800'],
  },
};

export function setup() {
  const login = http.post(
    `${BASE}/api/auth/login`,
    JSON.stringify({ email: EMAIL, password: PASS }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  check(login, { 'login ok': (r) => r.status === 200 });
  const token = login.json('data.auth_token');
  if (!token) {
    throw new Error('login failed');
  }
  return { token };
}

export default function (data) {
  const auth = { Authorization: `Bearer ${data.token}` };
  const paths = [
    '/api/auth/publickey',
    '/api/admin/agents',
    '/api/admin/users',
  ];

  for (const path of paths) {
    const headers = path.includes('publickey') ? {} : auth;
    const res = http.get(`${BASE}${path}`, { headers, tags: { name: path } });
    check(res, {
      [`${path} status`]: (r) => r.status >= 200 && r.status < 500,
    });
  }
  sleep(Number(__ENV.K6_SLEEP || 1));
}

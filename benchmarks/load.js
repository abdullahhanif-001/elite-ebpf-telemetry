/**
 * Elite load test — k6 HTTP flood against TARGET_URL.
 *
 * Env:
 *   TARGET_URL  HTTP endpoint (default http://localhost:8080/)
 *
 * PM2-safe: use localhost closed port or non-PM2 port for stress-only runs.
 * Example:
 *   docker run --rm --network host -e TARGET_URL=http://127.0.0.1:3001/ \
 *     -v $PWD/benchmarks/load.js:/scripts/load.js grafana/k6 run /scripts/load.js
 */
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '60s',
};

export default function () {
  const url = __ENV.TARGET_URL || 'http://localhost:8080/';
  http.get(url);
  sleep(0.01);
}

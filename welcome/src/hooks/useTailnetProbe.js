import { useEffect, useState } from 'react';

/**
 * Probes whether the browser can reach a tailnet-only endpoint.
 *
 * The probe target is served by Caddy on `probe.jackalope.network`,
 * which resolves to the server's tailnet IP. A device on the tailnet
 * can reach it; a device on the public internet cannot (the CGNAT
 * address is not routable).
 *
 * Returns one of:
 *   'pending'  - request is in flight
 *   'online'   - probe succeeded, client is on the tailnet
 *   'offline'  - probe failed (network error, timeout, or non-2xx)
 */
export function useTailnetProbe() {
  const [state, setState] = useState('pending');

  useEffect(() => {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3000);

    fetch('https://probe.jackalope.network/ok', {
      method: 'GET',
      mode: 'cors',
      cache: 'no-store',
      signal: controller.signal,
    })
      .then((res) => {
        clearTimeout(timeoutId);
        setState(res.ok ? 'online' : 'offline');
      })
      .catch(() => {
        clearTimeout(timeoutId);
        setState('offline');
      });

    return () => {
      clearTimeout(timeoutId);
      controller.abort();
    };
  }, []);

  return state;
}

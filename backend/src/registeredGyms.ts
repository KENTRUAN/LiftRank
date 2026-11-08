import { readFileSync } from 'node:fs';
import { finite, key, text, distanceMeters, type Location } from './core.js';

/** LiftRank-owned presets. No Places call or location history is needed. */
export function registeredGyms() {
  const path = process.env.REGISTERED_GYMS_FILE;
  // Address: recreation.duke.edu/wilson-recreation-center/
  // On-site coordinate: eprint.oit.duke.edu/printers/1178 (verified 2026-11-07).
  const raw: unknown = path ? JSON.parse(readFileSync(path, 'utf8')) : [{
    id: 'duke-wilson', name: 'Duke Wilson Recreation Center', address: '330 Towerview Road, Durham, NC 27708',
    latitude: 35.997085, longitude: -78.940951,
  }];
  if (!Array.isArray(raw)) throw new Error('REGISTERED_GYMS_FILE must contain an array');
  return raw.map(value => ({ id: `registered-${key(value.id)}`, name: text(value.name, 100), address: text(value.address, 200),
    latitude: finite(value.latitude, -90, 90), longitude: finite(value.longitude, -180, 180), isDemo: false, kind: 'registered', visibility: 'public' }));
}
export function nearbyRegisteredGyms(point: Location) {
  return registeredGyms().map(gym => ({ ...gym, distanceMeters: distanceMeters(point, gym) }))
    .filter(gym => gym.distanceMeters <= 500).sort((a, b) => a.distanceMeters - b.distanceMeters);
}

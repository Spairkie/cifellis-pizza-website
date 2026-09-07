/*
 * Delivery address geocoding + distance/ETA, using free services that
 * need no API key and no signup:
 *
 * - Nominatim (OpenStreetMap) for turning an address into coordinates.
 * - OSRM's public demo router for driving distance and time between
 *   two points.
 *
 * TRADE-OFF, read this before relying on it for anything high-volume:
 * both are shared public instances meant for light, occasional use,
 * not production traffic. Nominatim's usage policy caps clients at
 * roughly 1 request/second, and OSRM's demo server offers no uptime
 * guarantee. For a single pizza shop's delivery orders this is very
 * unlikely to be a problem. If it ever becomes one (rate-limit errors
 * in the console, or the shop wants guaranteed uptime), the fix is a
 * paid geocoder — Google's Distance Matrix API, Mapbox, or
 * Distancematrix.ai's free 100k/month tier are the natural next steps,
 * and only this one file would need to change.
 *
 * Neither service gives turn-by-turn directions or live traffic. This
 * is an estimate to help the counter/driver plan, not a substitute for
 * the driver's own GPS app.
 */

/* Confirmed from the shop's own Street View location. */
const SHOP_LOCATION = { lat: 39.8125468, lon: -75.019359 };

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
const OSRM_URL = 'https://router.project-osrm.org/route/v1/driving';

/* Turns a free-text address into { lat, lon, displayName }, or null if
   it couldn't be found. Biased toward southern New Jersey so a bare
   street address without a city still resolves nearby. */
async function geocodeAddress(query){
  if (!query || query.trim().length < 4) return null;
  const params = new URLSearchParams({
    format: 'json',
    q: query,
    countrycodes: 'us',
    limit: '1',
    viewbox: '-75.35,40.05,-74.65,39.55', // rough South Jersey bounding box
    bounded: '0', // prefer the box but don't hard-exclude outside it
  });
  try{
    const res = await fetch(`${NOMINATIM_URL}?${params.toString()}`, {
      headers: { 'Accept': 'application/json' },
    });
    if (!res.ok) return null;
    const rows = await res.json();
    if (!rows || !rows.length) return null;
    return { lat: parseFloat(rows[0].lat), lon: parseFloat(rows[0].lon), displayName: rows[0].display_name };
  }catch(e){
    console.warn('geocodeAddress failed:', e);
    return null;
  }
}

/* Driving distance/time from the shop to a given point. Returns
   { miles, minutes } or null if the route couldn't be computed. */
async function routeFromShop(lat, lon){
  const url = `${OSRM_URL}/${SHOP_LOCATION.lon},${SHOP_LOCATION.lat};${lon},${lat}?overview=false`;
  try{
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    const route = data && data.routes && data.routes[0];
    if (!route) return null;
    return {
      miles: Math.round((route.distance / 1609.34) * 10) / 10,
      minutes: Math.round(route.duration / 60),
    };
  }catch(e){
    console.warn('routeFromShop failed:', e);
    return null;
  }
}

/* Combines both calls: address text in, { lat, lon, miles, minutes,
   displayName } or null out. */
async function lookupDelivery(addressText){
  const geo = await geocodeAddress(addressText);
  if (!geo) return null;
  const route = await routeFromShop(geo.lat, geo.lon);
  if (!route) return { ...geo, miles: null, minutes: null };
  return { ...geo, ...route };
}

/* Wires an address <input> to show a live distance/ETA line beneath it
   once the visitor pauses typing. Debounced to respect Nominatim's
   rate limit and avoid firing on every keystroke.
     inputEl:  the address text input
     resultEl: an element to write the result line into
     onResult: optional callback(result|null) — result is what
               lookupDelivery() returns, or null on failure/too-short
               input. Use this to store distance/ETA on the order. */
function wireDeliveryLookup(inputEl, resultEl, onResult){
  let timer = null;
  let requestId = 0;
  inputEl.addEventListener('input', () => {
    clearTimeout(timer);
    const value = inputEl.value;
    if (value.trim().length < 6){
      resultEl.textContent = '';
      if (onResult) onResult(null);
      return;
    }
    resultEl.textContent = 'Checking address...';
    const myRequest = ++requestId;
    timer = setTimeout(async () => {
      const result = await lookupDelivery(value);
      if (myRequest !== requestId) return; // a newer keystroke superseded this lookup
      if (!result){
        resultEl.textContent = "Couldn't verify that address — you can still submit, we'll call to confirm.";
        if (onResult) onResult(null);
        return;
      }
      if (result.miles == null){
        resultEl.textContent = 'Address found, but distance could not be estimated.';
        if (onResult) onResult(result);
        return;
      }
      const farNote = result.miles > 8 ? ' — that\'s outside our usual delivery range, we may need to call you.' : '';
      resultEl.textContent = `~${result.miles} mi from the shop, about ${result.minutes} min drive${farNote}`;
      if (onResult) onResult(result);
    }, 900);
  });
}

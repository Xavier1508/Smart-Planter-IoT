// Read-only fixture for the fields and query used by CloudTelemetry.
// It does not implement Supabase authentication, RLS, or Realtime.
const http = require('http');

const deviceId = '00000000-0000-4000-8000-000000000001';
const rows = [
  { id: 3, device_id: deviceId, recorded_at: '2026-10-29T14:00:00Z', soil_percent: null, temperature_c: 26.5, humidity_percent: 64, light_percent: 90, uv_index: null },
  { id: 2, device_id: deviceId, recorded_at: '2026-10-29T12:30:00Z', soil_percent: null, temperature_c: 25, humidity_percent: 61, light_percent: 20, uv_index: null },
  { id: 1, device_id: deviceId, recorded_at: '2026-10-29T12:00:00Z', soil_percent: null, temperature_c: 24, humidity_percent: 60, light_percent: 10, uv_index: null },
];
const expectedColumns = 'id,device_id,recorded_at,soil_percent,temperature_c,humidity_percent,light_percent,uv_index';

http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const json = (status, body) => {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (req.method !== 'GET' || url.pathname !== '/rest/v1/planter_readings') {
    return json(501, { message: 'Fixture does not implement this endpoint' });
  }
  if (url.searchParams.get('select') !== expectedColumns ||
      url.searchParams.get('device_id') !== `eq.${deviceId}` ||
      url.searchParams.get('order') !== 'recorded_at.desc.nullslast,id.desc.nullslast' ||
      url.searchParams.get('limit') !== '1000') {
    return json(400, { message: 'Unexpected readings query' });
  }
  return json(200, rows);
}).listen(process.env.PORT || 4500);

import test from 'node:test';
import assert from 'node:assert/strict';

// The functions under test are pure, but `goldenHour.js` also reaches the
// database, and importing it pulls in `appConfig.js`, which refuses to load
// without Supabase credentials. CI has no secrets, so stand in placeholders and
// import dynamically — a static import would be hoisted above these lines and
// throw before they ran. Nothing here opens a connection.
process.env.SUPABASE_URL ||= 'http://supabase.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY ||= 'test-key';

const { cairoDateNow, timeToMinutes, windowOccurrenceKey } = await import('./goldenHour.js');

// The occurrence key is what makes the app's Golden Hour card once-per-window
// rather than once-per-launch, so what matters here is that two moments inside
// one run of a window produce the same key and two different runs never do.

const inWindow = ({ mode, start, end, at, date }) => windowOccurrenceKey({
  mode,
  startMinutes: timeToMinutes(start),
  endMinutes: timeToMinutes(end),
  nowMinutes: timeToMinutes(at),
  businessDate: date
});

test('the same window on the same day is one key however often it is asked', () => {
  const afternoon = { mode: 'afternoon', start: '11:00', end: '16:00', date: '2026-08-10' };

  assert.equal(inWindow({ ...afternoon, at: '13:00' }), 'afternoon:2026-08-10');
  assert.equal(inWindow({ ...afternoon, at: '15:59' }), 'afternoon:2026-08-10');
});

test('a different window is a different key, so the next card still shows', () => {
  assert.notEqual(
    inWindow({ mode: 'afternoon', start: '11:00', end: '16:00', at: '13:00', date: '2026-08-10' }),
    inWindow({ mode: 'sunset', start: '16:00', end: '19:00', at: '17:00', date: '2026-08-10' })
  );
});

test('tomorrow is a different key, which is the daily reset', () => {
  assert.equal(
    inWindow({ mode: 'afternoon', start: '11:00', end: '16:00', at: '13:00', date: '2026-08-11' }),
    'afternoon:2026-08-11'
  );
});

// Evening runs 19:00–02:00 by default. Opening at 00:30 is still the run that
// opened at 19:00 yesterday — dating it today would re-show a card the customer
// dismissed a few hours earlier.
test('a window that wraps past midnight is dated by the day it opened', () => {
  const evening = { mode: 'evening', start: '19:00', end: '02:00' };

  assert.equal(inWindow({ ...evening, at: '20:00', date: '2026-08-10' }), 'evening:2026-08-10');
  assert.equal(inWindow({ ...evening, at: '00:30', date: '2026-08-11' }), 'evening:2026-08-10');
  assert.equal(inWindow({ ...evening, at: '01:59', date: '2026-08-11' }), 'evening:2026-08-10');
});

test('stepping back over a month or year boundary stays a real date', () => {
  const evening = { mode: 'evening', start: '19:00', end: '02:00', at: '00:30' };

  assert.equal(inWindow({ ...evening, date: '2026-09-01' }), 'evening:2026-08-31');
  assert.equal(inWindow({ ...evening, date: '2027-01-01' }), 'evening:2026-12-31');
  assert.equal(inWindow({ ...evening, date: '2028-03-01' }), 'evening:2028-02-29');
});

test('the business date is Cairo\'s, not the server\'s', () => {
  // 22:30 UTC on 9 Aug is already 00:30 on 10 Aug in Cairo (UTC+2/+3).
  assert.equal(cairoDateNow(new Date('2026-08-09T22:30:00Z')), '2026-08-10');
  assert.equal(cairoDateNow(new Date('2026-08-09T10:00:00Z')), '2026-08-09');
});

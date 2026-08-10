// Cairo business-date helpers.
//
// The module keeps its own copy rather than importing from analyticsRoutes.js,
// where equivalents live privately. That is a deliberate trade: this module is
// self-contained by design (see server/forecast/README.md), and reaching into a
// route file for date maths would couple the model to a page's refactoring.
// The duplication is ~30 lines of pure functions with no state.
//
// A "business date" is a Cairo calendar day, matching orders.business_date,
// which Postgres defaults to (now() AT TIME ZONE 'Africa/Cairo')::date. Every
// date in this module is a 'YYYY-MM-DD' string in that frame — never a Date,
// never UTC — so there is one representation and no room to mix them up.

import { BUSINESS_TIME_ZONE } from './config.js';

const DAY_MS = 24 * 60 * 60 * 1000;

// Milliseconds to add to a UTC instant to get Cairo wall-clock time, honouring
// whatever offset (including DST) is in effect at that instant.
function cairoOffsetMs(date) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BUSINESS_TIME_ZONE,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).formatToParts(date).reduce((acc, part) => {
    acc[part.type] = part.value;
    return acc;
  }, {});

  const asUTC = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour === '24' ? '0' : parts.hour),
    Number(parts.minute),
    Number(parts.second)
  );
  return asUTC - date.getTime();
}

// 'YYYY-MM-DD' for the Cairo day an instant belongs to.
export function cairoDateKey(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: BUSINESS_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(date);
}

export function todayInCairo() {
  return cairoDateKey(new Date());
}

export function yesterdayInCairo() {
  return addDays(todayInCairo(), -1);
}

// Date arithmetic is done at UTC noon on the parsed date rather than midnight,
// so a DST shift can never round the result into the neighbouring day.
export function addDays(dateKey, days) {
  const [year, month, day] = dateKey.split('-').map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, day, 12) + days * DAY_MS);
  return `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, '0')}-${String(shifted.getUTCDate()).padStart(2, '0')}`;
}

// 0 = Sunday. Matches JavaScript's getUTCDay and location_opening_hours.day_of_week,
// and is the index used throughout for dow_index / dow_obs_count arrays.
export function dayOfWeek(dateKey) {
  const [year, month, day] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day, 12)).getUTCDay();
}

export function daysBetween(fromKey, toKey) {
  const parse = (key) => {
    const [year, month, day] = key.split('-').map(Number);
    return Date.UTC(year, month - 1, day, 12);
  };
  return Math.round((parse(toKey) - parse(fromKey)) / DAY_MS);
}

// Inclusive range of business dates, ascending. Returns [] when `to` precedes
// `from`, which is what makes "catch up from last run to yesterday" a no-op
// rather than an error on a day that has already been processed.
export function dateRange(fromKey, toKey) {
  const span = daysBetween(fromKey, toKey);
  if (span < 0) return [];
  return Array.from({ length: span + 1 }, (_, i) => addDays(fromKey, i));
}

export function isValidDateKey(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

// UTC instants bounding a Cairo business date, for querying timestamptz columns
// (created_at) rather than the date column.
export function cairoDayBoundsUtc(dateKey) {
  const [year, month, day] = dateKey.split('-').map(Number);
  const approxNoon = new Date(Date.UTC(year, month - 1, day, 12));
  const offset = cairoOffsetMs(approxNoon);
  const start = new Date(Date.UTC(year, month - 1, day) - offset);
  return { start, end: new Date(start.getTime() + DAY_MS) };
}

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

/*
  Do the order routes ask Postgres for columns that exist?

  The pickup handoff shipped selecting `order_items.serving_count` and
  `order_items.product_image_url`. Neither is a column: both are derived in
  `enrichOrderItem` from the joined variant and product. Postgres answers 42703,
  the route turns that into `lookup_failed`, and an attendant mid-handover reads
  "column order_items.serving_count does not exist" off a phone.

  Nothing caught it, because the one thing that would have — running the query —
  needs the live database, and this app has no fixture for that. What the repo
  does carry is `db/schema/`, a read-only capture of the real schema. It is not
  the source of truth, but it is a faithful copy of the column names, and column
  names are exactly what this mistake gets wrong.

  So: read the select lists straight out of the route file, and check every bare
  column against the capture. Embedded resources — `products(image_url)` — are a
  different question (they resolve through foreign keys, not columns here) and
  are skipped along with `*`.
*/

const routeSource = readFileSync(new URL('./orderRoutes.js', import.meta.url), 'utf8');
const schemaSource = readFileSync(new URL('../../db/schema/10_tables.sql', import.meta.url), 'utf8');

// Tables whose selects this test polices. Extend it as routes reach further.
const TABLES = ['orders', 'order_items', 'order_handoffs'];

function columnsOf(table) {
  const match = schemaSource.match(
    new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${table} \\(([\\s\\S]*?)\\n\\);`)
  );
  assert.ok(match, `${table} is missing from the schema capture`);

  return new Set(
    match[1]
      .split('\n')
      .map((line) => line.trim().match(/^([a-z_][a-z0-9_]*)\s/))
      .filter(Boolean)
      .map((columnMatch) => columnMatch[1])
  );
}

// `.from('x')` and its `.select('…')` are separated by a newline and indentation
// in this file, and occasionally by nothing at all. The select has to be the one
// belonging to *this* chain: stop at the next `.from(`, or a query that never
// selects will borrow the select of the query after it and be judged against the
// wrong table.
function selectsFor(table) {
  const found = [];
  const from = new RegExp(`\\.from\\('${table}'\\)`, 'g');
  let match;

  while ((match = from.exec(routeSource)) !== null) {
    const rest = routeSource.slice(match.index + match[0].length);
    const nextFrom = rest.search(/\.from\(\s*'/);
    const chain = nextFrom === -1 ? rest : rest.slice(0, nextFrom);
    const select = chain.match(/^\s*\.select\(\s*'([^']*)'/);
    if (select) found.push(select[1]);
  }

  return found;
}

// Drop embedded resources — `products(image_url)`, and any nesting inside them —
// leaving only the columns asked for on the table itself.
function bareColumns(selectList) {
  let remaining = selectList;
  let previous;

  do {
    previous = remaining;
    remaining = remaining.replace(/[a-z_][a-z0-9_]*\s*\([^()]*\)/gi, '');
  } while (remaining !== previous);

  return remaining
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry && entry !== '*');
}

for (const table of TABLES) {
  test(`every ${table} column selected in orderRoutes.js exists`, () => {
    const columns = columnsOf(table);
    const selects = selectsFor(table);
    assert.ok(selects.length > 0, `no ${table} selects found — has the query style changed?`);

    for (const selectList of selects) {
      for (const column of bareColumns(selectList)) {
        assert.ok(
          columns.has(column),
          `orderRoutes.js selects ${table}.${column}, which is not a column in db/schema.\n  select: ${selectList}`
        );
      }
    }
  });
}

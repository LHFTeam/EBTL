export function clean(obj = {}) {
  return Object.fromEntries(
    Object.entries(obj).filter(([, value]) => value !== undefined && value !== '')
  );
}

export function normalizeEmptyStrings(value) {
  if (value === '') return undefined;

  if (Array.isArray(value)) {
    return value.map(normalizeEmptyStrings);
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value)
        .map(([key, val]) => [key, normalizeEmptyStrings(val)])
        .filter(([, val]) => val !== undefined)
    );
  }

  return value;
}

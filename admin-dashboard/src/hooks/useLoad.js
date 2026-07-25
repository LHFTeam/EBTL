import { useEffect, useState } from 'react';

export function useLoad(loader, deps = []) {
  const [state, setState] = useState({ loading: true, refreshing: false, error: '', data: null });
  const load = async () => {
    // Keep any data we already have on screen while refetching (stale-while-revalidate)
    // so a reload after a save does not blank the whole page.
    setState(s => ({ ...s, loading: s.data === null, refreshing: s.data !== null, error: '' }));
    try {
      setState({ loading: false, refreshing: false, error: '', data: await loader() });
    } catch (e) {
      setState(s => ({ ...s, loading: false, refreshing: false, error: e.message }));
    }
  };
  useEffect(() => { load(); }, deps);
  return { ...state, reload: load };
}

import { useEffect, useState } from 'react';

export function useLoad(loader, deps = []) {
  const [state, setState] = useState({ loading: true, error: '', data: null });
  const load = async () => { setState(s => ({ ...s, loading: true, error: '' })); try { setState({ loading: false, error: '', data: await loader() }); } catch (e) { setState({ loading: false, error: e.message, data: null }); } };
  useEffect(() => { load(); }, deps);
  return { ...state, reload: load };
}
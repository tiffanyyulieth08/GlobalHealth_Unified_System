import { useCallback, useEffect, useRef, useState } from "react";

type AsyncState<T> = {
  data: T | null;
  error: Error | null;
  isLoading: boolean;
};

export function useApi<T>(request: (signal: AbortSignal) => Promise<T>) {
  const requestRef = useRef(request);
  requestRef.current = request;
  const [requestKey, setRequestKey] = useState(0);
  const [state, setState] = useState<AsyncState<T>>({
    data: null,
    error: null,
    isLoading: true,
  });

  const retry = useCallback(() => setRequestKey((key) => key + 1), []);

  useEffect(() => {
    const controller = new AbortController();
    setState((current) => ({ ...current, error: null, isLoading: true }));

    requestRef
      .current(controller.signal)
      .then((data) => setState({ data, error: null, isLoading: false }))
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") {
          return;
        }
        setState({
          data: null,
          error: error instanceof Error ? error : new Error("Error inesperado"),
          isLoading: false,
        });
      });

    return () => controller.abort();
  }, [requestKey]);

  return { ...state, retry };
}

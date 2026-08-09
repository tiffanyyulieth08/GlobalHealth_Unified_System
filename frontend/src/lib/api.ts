const DEFAULT_API_BASE_URL = "http://localhost:8000";

export const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL
).replace(/\/$/, "");

type ApiErrorPayload = {
  detail?: string;
  message?: string;
};

export type ApiResult<T> = {
  data: T;
  ok: boolean;
  status: number;
};

export class ApiError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

async function parseResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    let payload: ApiErrorPayload | undefined;
    try {
      payload = (await response.json()) as ApiErrorPayload;
    } catch {
      payload = undefined;
    }

    throw new ApiError(
      payload?.detail || payload?.message || "No se pudo completar la solicitud.",
      response.status,
    );
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}

export async function apiRequest<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const headers = new Headers(options.headers);
  if (options.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  headers.set("Accept", "application/json");

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...options,
      headers,
      signal: options.signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw error;
    }
    throw new ApiError(
      "No fue posible conectar con el servicio. Verifica que la API esté disponible.",
      0,
    );
  }

  return parseResponse<T>(response);
}

export async function apiRequestResult<T>(
  path: string,
  signal?: AbortSignal,
): Promise<ApiResult<T>> {
  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      headers: { Accept: "application/json" },
      method: "GET",
      signal,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw error;
    }
    throw new ApiError(
      "No fue posible conectar con el servicio. Verifica que la API esté disponible.",
      0,
    );
  }

  let data: T;
  try {
    data = (await response.json()) as T;
  } catch {
    throw new ApiError("El servicio devolvió una respuesta no válida.", response.status);
  }

  return { data, ok: response.ok, status: response.status };
}

export const api = {
  get<T>(path: string, signal?: AbortSignal) {
    return apiRequest<T>(path, { method: "GET", signal });
  },
  getResult<T>(path: string, signal?: AbortSignal) {
    return apiRequestResult<T>(path, signal);
  },
  post<T>(path: string, body?: unknown, signal?: AbortSignal) {
    return apiRequest<T>(path, {
      method: "POST",
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
  },
  patch<T>(path: string, body: unknown, signal?: AbortSignal) {
    return apiRequest<T>(path, {
      method: "PATCH",
      body: JSON.stringify(body),
      signal,
    });
  },
  delete<T>(path: string, signal?: AbortSignal) {
    return apiRequest<T>(path, { method: "DELETE", signal });
  },
};

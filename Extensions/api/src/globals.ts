// The web APIs extensions expect that a bare JavaScriptCore context doesn't have: console, timers, fetch,
// URLSearchParams and crypto.randomUUID. They're defined before React loads, since its scheduler looks for its timer
// functions once, when it starts.
import { call, native, post } from "./native";

const global = globalThis as Record<string, unknown>;

function describe(value: unknown): string {
  if (typeof value === "string") return value;
  if (value instanceof Error) return value.stack ? `${value.message}\n${value.stack}` : value.message;
  try {
    return JSON.stringify(value) ?? String(value);
  } catch {
    return String(value);
  }
}

function log(level: string) {
  return (...args: unknown[]) => post({ type: "log", level, message: args.map(describe).join(" ") });
}

global.console = {
  log: log("log"),
  info: log("info"),
  debug: log("debug"),
  warn: log("warn"),
  error: log("error"),
};

// Intervals keep one id while each tick is scheduled as a new native timeout.
const intervals = new Map<number, number>();
let nextIntervalID = -1;

global.setTimeout = (callback: (...args: unknown[]) => void, milliseconds = 0, ...args: unknown[]) =>
  native.setTimeout(() => callback(...args), Math.max(0, Number(milliseconds) || 0));
global.clearTimeout = (id?: number) => {
  if (id !== undefined) native.clearTimeout(id);
};
global.setImmediate = (callback: (...args: unknown[]) => void, ...args: unknown[]) =>
  native.setTimeout(() => callback(...args), 0);
global.clearImmediate = global.clearTimeout;
global.setInterval = (callback: (...args: unknown[]) => void, milliseconds = 0, ...args: unknown[]) => {
  const id = nextIntervalID--;
  const delay = Math.max(1, Number(milliseconds) || 0);
  const tick = () => {
    if (!intervals.has(id)) return;
    intervals.set(id, native.setTimeout(tick, delay));
    callback(...args);
  };
  intervals.set(id, native.setTimeout(tick, delay));
  return id;
};
global.clearInterval = (id?: number) => {
  if (id === undefined) return;
  const timeout = intervals.get(id);
  intervals.delete(id);
  if (timeout !== undefined) native.clearTimeout(timeout);
};
if (typeof global.queueMicrotask !== "function") {
  global.queueMicrotask = (callback: () => void) => {
    Promise.resolve().then(callback);
  };
}

const start = Date.now();
global.performance = { now: () => Date.now() - start };
global.crypto = { randomUUID: () => native.uuid() };

class URLSearchParamsShim {
  private entries: [string, string][] = [];

  constructor(init?: string | Record<string, string> | [string, string][]) {
    if (typeof init === "string") {
      for (const part of init.replace(/^\?/, "").split("&")) {
        if (!part) continue;
        const [key, value = ""] = part.split("=");
        this.entries.push([decode(key), decode(value)]);
      }
    } else if (Array.isArray(init)) {
      this.entries = init.map(([key, value]) => [String(key), String(value)]);
    } else if (init) {
      this.entries = Object.entries(init).map(([key, value]) => [key, String(value)]);
    }
  }

  append(key: string, value: string) {
    this.entries.push([key, String(value)]);
  }

  set(key: string, value: string) {
    this.delete(key);
    this.append(key, value);
  }

  get(key: string) {
    return this.entries.find(([name]) => name === key)?.[1] ?? null;
  }

  getAll(key: string) {
    return this.entries.filter(([name]) => name === key).map(([, value]) => value);
  }

  has(key: string) {
    return this.entries.some(([name]) => name === key);
  }

  delete(key: string) {
    this.entries = this.entries.filter(([name]) => name !== key);
  }

  forEach(callback: (value: string, key: string) => void) {
    for (const [key, value] of this.entries) callback(value, key);
  }

  toString() {
    return this.entries.map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`).join("&");
  }
}

function decode(text: string) {
  return decodeURIComponent(text.replace(/\+/g, " "));
}

if (typeof global.URLSearchParams !== "function") {
  global.URLSearchParams = URLSearchParamsShim;
}

class HeadersShim {
  private map = new Map<string, string>();

  constructor(init?: Record<string, string> | [string, string][] | HeadersShim) {
    if (init instanceof HeadersShim) {
      init.forEach((value, key) => this.set(key, value));
    } else if (Array.isArray(init)) {
      for (const [key, value] of init) this.append(key, value);
    } else if (init) {
      for (const [key, value] of Object.entries(init)) this.set(key, value);
    }
  }

  get(name: string) {
    return this.map.get(name.toLowerCase()) ?? null;
  }

  set(name: string, value: string) {
    this.map.set(name.toLowerCase(), String(value));
  }

  append(name: string, value: string) {
    const existing = this.get(name);
    this.set(name, existing === null ? value : `${existing}, ${value}`);
  }

  has(name: string) {
    return this.map.has(name.toLowerCase());
  }

  delete(name: string) {
    this.map.delete(name.toLowerCase());
  }

  forEach(callback: (value: string, key: string) => void) {
    this.map.forEach((value, key) => callback(value, key));
  }

  entries() {
    return this.map.entries();
  }

  toObject() {
    return Object.fromEntries(this.map);
  }
}

class ResponseShim {
  readonly ok: boolean;
  readonly status: number;
  readonly statusText: string;
  readonly headers: HeadersShim;
  readonly url: string;
  bodyUsed = false;

  constructor(
    private readonly body: string,
    init: { status?: number; statusText?: string; headers?: Record<string, string>; url?: string } = {},
  ) {
    this.status = init.status ?? 200;
    this.ok = this.status >= 200 && this.status < 300;
    this.statusText = init.statusText ?? "";
    this.headers = new HeadersShim(init.headers);
    this.url = init.url ?? "";
  }

  async text() {
    this.bodyUsed = true;
    return this.body;
  }

  async json() {
    return JSON.parse(await this.text());
  }
}

interface FetchInit {
  method?: string;
  headers?: Record<string, string> | [string, string][] | HeadersShim;
  body?: string | URLSearchParamsShim | null;
}

/** Text bodies only for now. Whippet rejects hosts the manifest doesn't list before sending anything. */
async function fetchShim(input: string | { url?: string; href?: string }, init: FetchInit = {}) {
  const url = typeof input === "string" ? input : (input.url ?? input.href ?? String(input));
  const headers = new HeadersShim(init.headers).toObject();
  const body = init.body == null ? undefined : String(init.body);
  if (init.body instanceof URLSearchParamsShim && !("content-type" in headers)) {
    headers["content-type"] = "application/x-www-form-urlencoded;charset=UTF-8";
  }
  const response = await call<{
    status: number;
    statusText: string;
    headers: Record<string, string>;
    url: string;
    body: string;
  }>("fetch", { url, method: (init.method ?? "GET").toUpperCase(), headers, body });
  return new ResponseShim(response.body, response);
}

global.Headers = HeadersShim;
global.Response = ResponseShim;
global.fetch = fetchShim;

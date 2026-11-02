/**
 * The functions Whippet injects into each extension's JavaScript context before the runtime runs. Everything an
 * extension can reach outside its own code goes through these, and every message is a JSON string, so the runtime could
 * move into a separate process without changing the API.
 */
export interface Native {
  /** Sends a message to Whippet: a rendered tree, a finished command, an error or a log line. */
  post(message: string): void;
  /** Asks Whippet to do something on the extension's behalf, resolving with a JSON string, or rejecting with a reason. */
  call(name: string, args: string): Promise<string>;
  setTimeout(callback: () => void, milliseconds: number): number;
  clearTimeout(id: number): void;
  uuid(): string;
}

declare const __native: Native;

export const native: Native = __native;

/** A message to Whippet. */
export type Message =
  | { type: "render"; session: string; depth: number; tree: SerializedNode | null }
  | { type: "done"; session: string }
  | { type: "error"; session?: string; message: string; stack?: string }
  | { type: "log"; level: string; message: string };

/** A host element as Whippet receives it. Functions in its props become `{ $handler: id }`. */
export interface SerializedNode {
  id: number;
  type: string;
  props: Record<string, unknown>;
  children: SerializedNode[];
}

export function post(message: Message): void {
  native.post(JSON.stringify(message));
}

/** Calls Whippet and parses its answer. */
export async function call<T = unknown>(name: string, args: unknown = null): Promise<T> {
  const result = await native.call(name, JSON.stringify(args ?? null));
  return (result === "" ? undefined : JSON.parse(result)) as T;
}

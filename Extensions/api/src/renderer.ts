// A React renderer whose host elements are plain objects. After each commit, the top view of a session is serialized
// to JSON and sent to Whippet, which draws it natively. Functions in props stay here, registered under ids Whippet
// sends back when the user acts.
import { createContext, type ReactNode } from "react";
import Reconciler from "react-reconciler";
import { ConcurrentRoot, DefaultEventPriority, DiscreteEventPriority, NoEventPriority } from "react-reconciler/constants";
import { post, type SerializedNode } from "./native";

export interface Instance {
  id: number;
  type: string;
  props: Record<string, unknown>;
  children: Instance[];
  /** Text between tags isn't drawn; it's kept so React can insert and remove it like any child. */
  text?: string;
}

export interface Container {
  session: string;
  children: Instance[];
}

let nextInstanceID = 1;
let currentUpdatePriority = NoEventPriority;

function createInstanceNode(type: string, props: Record<string, unknown>): Instance {
  return { id: nextInstanceID++, type, props, children: [] };
}

function remove(list: Instance[], child: Instance) {
  const index = list.indexOf(child);
  if (index >= 0) list.splice(index, 1);
}

function insert(list: Instance[], child: Instance, before: Instance) {
  remove(list, child);
  const index = list.indexOf(before);
  list.splice(index < 0 ? list.length : index, 0, child);
}

const sessionsToSend = new Set<Container>();

function scheduleSend(container: Container) {
  if (sessionsToSend.size === 0) {
    queueMicrotask(() => {
      const containers = [...sessionsToSend];
      sessionsToSend.clear();
      for (const container of containers) send(container);
    });
  }
  sessionsToSend.add(container);
}

const hostConfig = {
  rendererPackageName: "@whippet/api",
  rendererVersion: "0.1.0",
  extraDevToolsConfig: null,
  supportsMutation: true,
  supportsPersistence: false,
  supportsHydration: false,
  supportsMicrotasks: true,
  supportsResources: false,
  supportsSingletons: false,
  supportsTestSelectors: false,
  isPrimaryRenderer: true,
  warnsIfNotActing: false,
  noTimeout: -1,
  NotPendingTransition: null,
  HostTransitionContext: createContext(null),

  createInstance: (type: string, props: Record<string, unknown>) => createInstanceNode(type, props),
  createTextInstance: (text: string) => ({ ...createInstanceNode("#text", {}), text }),
  appendInitialChild: (parent: Instance, child: Instance) => parent.children.push(child),
  finalizeInitialChildren: () => false,
  shouldSetTextContent: () => false,
  getRootHostContext: () => null,
  getChildHostContext: (parentContext: null) => parentContext,
  getPublicInstance: (instance: Instance) => instance,
  prepareForCommit: () => null,
  resetAfterCommit: (container: Container) => scheduleSend(container),
  preparePortalMount: () => {},
  scheduleTimeout: (callback: () => void, delay?: number) => setTimeout(callback, delay),
  cancelTimeout: (id: number) => clearTimeout(id),
  scheduleMicrotask: (callback: () => void) => queueMicrotask(callback),
  getInstanceFromNode: () => null,
  beforeActiveInstanceBlur: () => {},
  afterActiveInstanceBlur: () => {},
  prepareScopeUpdate: () => {},
  getInstanceFromScope: () => null,
  detachDeletedInstance: () => {},
  bindToConsole: (method: string, args: unknown[]) =>
    (console as unknown as Record<string, (...args: unknown[]) => void>)[method]?.bind(console, ...args),

  appendChild: (parent: Instance, child: Instance) => {
    remove(parent.children, child);
    parent.children.push(child);
  },
  appendChildToContainer: (container: Container, child: Instance) => {
    remove(container.children, child);
    container.children.push(child);
  },
  insertBefore: (parent: Instance, child: Instance, before: Instance) => insert(parent.children, child, before),
  insertInContainerBefore: (container: Container, child: Instance, before: Instance) =>
    insert(container.children, child, before),
  removeChild: (parent: Instance, child: Instance) => remove(parent.children, child),
  removeChildFromContainer: (container: Container, child: Instance) => remove(container.children, child),
  resetTextContent: () => {},
  commitTextUpdate: (instance: Instance, _old: string, text: string) => {
    instance.text = text;
  },
  commitMount: () => {},
  commitUpdate: (instance: Instance, _type: string, _old: unknown, props: Record<string, unknown>) => {
    instance.props = props;
  },
  hideInstance: (instance: Instance) => {
    instance.props = { ...instance.props, hidden: true };
  },
  hideTextInstance: () => {},
  unhideInstance: (instance: Instance, props: Record<string, unknown>) => {
    instance.props = props;
  },
  unhideTextInstance: () => {},
  clearContainer: (container: Container) => {
    container.children = [];
  },

  setCurrentUpdatePriority: (priority: number) => {
    currentUpdatePriority = priority;
  },
  getCurrentUpdatePriority: () => currentUpdatePriority,
  resolveUpdatePriority: () => (currentUpdatePriority !== NoEventPriority ? currentUpdatePriority : DefaultEventPriority),
  resetFormInstance: () => {},
  requestPostPaintCallback: () => {},
  shouldAttemptEagerTransition: () => false,
  trackSchedulerEvent: () => {},
  resolveEventType: () => null,
  resolveEventTimeStamp: () => -1.1,
  maySuspendCommit: () => false,
  maySuspendCommitOnUpdate: () => false,
  maySuspendCommitInSyncRender: () => false,
  preloadInstance: () => true,
  startSuspendingCommit: () => null,
  suspendInstance: () => {},
  suspendOnActiveViewTransition: () => {},
  waitForCommitToBeReady: () => null,
  getSuspendedCommitReason: () => null,
};

// The host config is typed loosely on purpose: the reconciler's types list every optional feature, and this renderer
// implements the mutation subset.
const reconciler = Reconciler(hostConfig as never);

interface Session {
  container: Container;
  root: unknown;
  handlers: Map<string, (...args: unknown[]) => unknown>;
}

const sessions = new Map<string, Session>();

function reportError(session: string | undefined, error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const stack = error instanceof Error ? error.stack : undefined;
  post({ type: "error", session, message, stack });
}

/** Starts rendering `element` for a session. */
export function mount(session: string, element: ReactNode) {
  const container: Container = { session, children: [] };
  const root = reconciler.createContainer(
    container,
    ConcurrentRoot,
    null,
    false,
    null,
    session,
    (error: unknown) => reportError(session, error),
    (error: unknown) => reportError(session, error),
    (error: unknown) => reportError(session, error),
    () => {},
    null,
  );
  sessions.set(session, { container, root, handlers: new Map() });
  reconciler.updateContainer(element, root as never, null, null);
}

/** Unmounts a session's tree, which runs its effects' cleanups. */
export function unmount(session: string) {
  const entry = sessions.get(session);
  if (!entry) return;
  reconciler.updateContainer(null, entry.root as never, null, () => sessions.delete(session));
}

/** Runs a handler Whippet was sent, at the priority of a user's input so its updates commit straight away. */
export function dispatch(session: string, handler: string, args: unknown[]) {
  const callback = sessions.get(session)?.handlers.get(handler);
  if (!callback) return;
  const previous = currentUpdatePriority;
  currentUpdatePriority = DiscreteEventPriority;
  try {
    const result = callback(...args);
    if (result instanceof Promise) result.catch((error) => reportError(session, error));
  } catch (error) {
    reportError(session, error);
  } finally {
    currentUpdatePriority = previous;
  }
}

function serialize(instance: Instance, handlers: Session["handlers"]): SerializedNode {
  const props: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(instance.props)) {
    if (key === "children" || value === undefined) continue;
    if (typeof value === "function") {
      const id = `${instance.id}.${key}`;
      handlers.set(id, value as (...args: unknown[]) => unknown);
      props[key] = { $handler: id };
    } else if (!(typeof value === "object" && value !== null && "$$typeof" in value)) {
      props[key] = value;
    }
  }
  const children = instance.children.filter((child) => child.type !== "#text").map((child) => serialize(child, handlers));
  return { id: instance.id, type: instance.type, props, children };
}

/** Sends the command's view, with how deep its history is and which entry it shows, so Whippet knows when it moved. */
function send(container: Container) {
  const entry = sessions.get(container.session);
  if (!entry) return;
  const view = container.children.find((child) => child.type === "view");
  entry.handlers.clear();
  post({
    type: "render",
    session: container.session,
    depth: Number(view?.props.depth ?? 1),
    route: String(view?.props.route ?? ""),
    tree: view ? serialize(view, entry.handlers) : null,
  });
}

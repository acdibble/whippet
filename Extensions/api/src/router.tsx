// Navigation within a command, as URL routing with a history, in the manner of react-router. A command starts at "/".
// `navigate` moves to another path, with optional state, and Escape goes back through the history, leaving the command
// from its first entry. The command's own component stays mounted throughout, so its state outlives navigation; what
// changes is what it renders, through <Routes> or by reading the location.
import {
  Children,
  Component,
  createContext,
  createElement,
  isValidElement,
  useContext,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactElement,
  type ReactNode,
} from "react";

export interface Location<State = unknown> {
  /** Such as `/fruit/apple`. */
  pathname: string;
  /** What was passed as `state` when navigating here, such as the item to show. */
  state: State;
  /** Unique to this entry in the history. */
  key: string;
}

export interface NavigateOptions {
  /** Replaces the current entry instead of adding one, so Escape doesn't come back to it. */
  replace?: boolean;
  state?: unknown;
}

export interface NavigateFunction {
  /** Goes to a path. One without a leading slash is relative to the current one, and `..` goes up a level. */
  (to: string, options?: NavigateOptions): void;
  /** Moves through the history: `-1` goes back, as Escape does. It stops at the first entry. */
  (delta: number): void;
}

interface Router {
  location: Location;
  navigate: NavigateFunction;
}

const root: Location = { pathname: "/", state: undefined, key: "0" };
const RouterContext = createContext<Router>({ location: root, navigate: () => {} });
const ParamsContext = createContext<Record<string, string>>({});

export function useLocation<State = unknown>(): Location<State> {
  return useContext(RouterContext).location as Location<State>;
}

export function useNavigate(): NavigateFunction {
  return useContext(RouterContext).navigate;
}

/** The values of the matched route's `:name` segments, and `*` for the rest of a path matched by a trailing `*`. */
export function useParams<Params extends Record<string, string> = Record<string, string>>(): Params {
  return useContext(ParamsContext) as Params;
}

export interface RouteProps {
  /** Such as `/`, `/fruit/:name` or `/docs/*`. */
  path: string;
  element: ReactNode;
}

/** Declares a route for `<Routes>`, which renders its `element` when the path matches. */
export function Route(_props: RouteProps): ReactElement | null {
  return null;
}

/** Renders the first `<Route>` whose path matches the current location, or nothing. */
export function Routes({ children }: { children?: ReactNode }) {
  const { location } = useContext(RouterContext);
  for (const child of Children.toArray(children)) {
    if (!isValidElement<RouteProps>(child)) continue;
    const params = matchPath(child.props.path, location.pathname);
    if (params) return createElement(ParamsContext.Provider, { value: params }, child.props.element);
  }
  return null;
}

function segments(path: string) {
  return path.split("/").filter(Boolean);
}

/** The params when `pathname` matches `pattern`, or null. */
export function matchPath(pattern: string, pathname: string): Record<string, string> | null {
  const expected = segments(pattern);
  const actual = segments(pathname);
  const params: Record<string, string> = {};
  for (let index = 0; index < expected.length; index++) {
    const part = expected[index];
    if (part === "*") {
      params["*"] = actual.slice(index).join("/");
      return params;
    }
    if (index >= actual.length) return null;
    if (part.startsWith(":")) {
      params[part.slice(1)] = decodeURIComponent(actual[index]);
    } else if (part !== actual[index]) {
      return null;
    }
  }
  return expected.length === actual.length ? params : null;
}

/** Resolves `to` against the current path, following `.` and `..`. */
export function resolvePath(to: string, from: string) {
  const parts = to.startsWith("/") ? [] : segments(from);
  for (const part of segments(to)) {
    if (part === "..") parts.pop();
    else if (part !== ".") parts.push(part);
  }
  return `/${parts.join("/")}`;
}

/** Lets Whippet go back from outside React, on Escape. */
export interface RouterController {
  /** Returns false on the first entry, so Whippet leaves the command. */
  back(): boolean;
  popToRoot(): void;
}

/**
 * Keeps a command's history and renders the command inside one `view`, whose depth and route key tell Whippet when it
 * went forward or back.
 */
export function RouterRoot({
  command,
  controller,
}: {
  command: ReactElement;
  controller: (controller: RouterController) => void;
}) {
  const [history, setHistory] = useState<Location[]>([root]);
  const nextKey = useRef(1);
  const location = history[history.length - 1];

  const navigate = useMemo(
    () =>
      ((to: string | number, options: NavigateOptions = {}) => {
        if (typeof to === "number") {
          if (to < 0) setHistory((current) => current.slice(0, Math.max(1, current.length + to)));
          return;
        }
        setHistory((current) => {
          const entry: Location = {
            pathname: resolvePath(to, current[current.length - 1].pathname),
            state: options.state,
            key: String(nextKey.current++),
          };
          return options.replace ? [...current.slice(0, -1), entry] : [...current, entry];
        });
      }) as NavigateFunction,
    [],
  );

  controller({
    back: () => {
      if (history.length <= 1) return false;
      navigate(-1);
      return true;
    },
    popToRoot: () => setHistory((current) => current.slice(0, 1)),
  });

  const router = useMemo(() => ({ location, navigate }), [location, navigate]);
  return createElement(
    RouterContext.Provider,
    { value: router },
    createElement(
      "view",
      { depth: history.length, route: location.key },
      createElement(ErrorBoundary, { resetKey: location.key }, command),
    ),
  );
}

interface ErrorBoundaryProps {
  children?: ReactNode;
  /** Clears the error when it changes, so navigating away from a broken page recovers. */
  resetKey: string;
}

/** Shows an error in place of a view that threw while rendering, rather than leaving the panel empty. */
class ErrorBoundary extends Component<ErrorBoundaryProps, { error: Error | null; resetKey: string }> {
  state = { error: null as Error | null, resetKey: this.props.resetKey };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  static getDerivedStateFromProps(props: ErrorBoundaryProps, state: { resetKey: string }) {
    return props.resetKey === state.resetKey ? null : { error: null, resetKey: props.resetKey };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error(error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const markdown = `## Something went wrong\n\n${error.message}\n\n\`\`\`\n${error.stack ?? ""}\n\`\`\``;
    return createElement("detail", { markdown });
  }
}

// What extensions import from "@whippet/api": the components Whippet draws natively, the actions they offer, and the
// functions that reach Whippet and the Mac.
import {
  Component,
  createContext,
  createElement,
  useContext,
  useMemo,
  useState,
  type ErrorInfo,
  type ReactElement,
  type ReactNode,
} from "react";
import { call } from "./native";

/** An SF Symbol name such as `"star.fill"`, an emoji, an `https` image URL or an image file in the extension's folder. */
export type Icon = string;

export type Modifier = "cmd" | "shift" | "opt" | "ctrl";

/** A key with modifiers, such as `{ modifiers: ["cmd"], key: "o" }`. */
export interface Shortcut {
  modifiers: Modifier[];
  key: string;
}

// Host elements are strings, which the renderer turns into plain objects.
function host(type: string, props: object, ...children: ReactNode[]) {
  return createElement(type, props, ...children);
}

// MARK: - List

export interface ListProps {
  children?: ReactNode;
  /** Shows a spinner in the search bar, while results load. */
  isLoading?: boolean;
  searchBarPlaceholder?: string;
  /** Shown in the search bar for views pushed onto the first. */
  navigationTitle?: string;
  /**
   * Called as the search text changes. Without it, Whippet filters the items itself by title, subtitle and keywords;
   * with it, the extension decides what to show, unless `filtering` is true.
   */
  onSearchTextChange?: (text: string) => void;
  /** Whether Whippet filters the items by the search text. Defaults to true unless `onSearchTextChange` is set. */
  filtering?: boolean;
  /** Waits until typing pauses before calling `onSearchTextChange`, for searches that go over the network. */
  throttle?: boolean;
  /** Actions offered while the list has no items. */
  actions?: ReactElement;
}

export interface Accessory {
  text?: string;
  icon?: Icon;
}

export interface ListItemProps {
  /** Keeps the item selected as the list changes. Defaults to the item's position. */
  id?: string;
  title: string;
  subtitle?: string;
  icon?: Icon;
  accessories?: Accessory[];
  /** More words the item is found by when Whippet filters. */
  keywords?: string[];
  /** The first action runs on Return, the second on ⌘Return, and all of them are in ⌘K. */
  actions?: ReactElement;
}

export interface ListSectionProps {
  title?: string;
  children?: ReactNode;
}

export function List({ children, actions, filtering, onSearchTextChange, ...props }: ListProps) {
  return host("list", { ...props, onSearchTextChange, filtering: filtering ?? !onSearchTextChange }, actions, children);
}

List.Item = function ListItem({ actions, ...props }: ListItemProps) {
  return host("list-item", props, actions);
};

List.Section = function ListSection({ children, ...props }: ListSectionProps) {
  return host("list-section", props, children);
};

// MARK: - Detail

export interface DetailProps {
  /** Markdown: headings, emphasis, links, lists and code. */
  markdown: string;
  navigationTitle?: string;
  isLoading?: boolean;
  actions?: ReactElement;
}

export function Detail({ actions, ...props }: DetailProps) {
  return host("detail", props, actions);
}

// MARK: - Form

/** The values of a form's fields when it's submitted, keyed by each field's `id`. */
export type FormValues = Record<string, string | boolean>;

export interface FormProps {
  children?: ReactNode;
  navigationTitle?: string;
  isLoading?: boolean;
  /** Return runs the first action, usually an `Action.SubmitForm`. */
  actions?: ReactElement;
}

interface FieldProps<Value> {
  id: string;
  title?: string;
  /** The value when the form opens. */
  defaultValue?: Value;
  /** Sets the value, replacing what was typed. */
  value?: Value;
  onChange?: (value: Value) => void;
}

export interface TextFieldProps extends FieldProps<string> {
  placeholder?: string;
}

export interface CheckboxProps extends FieldProps<boolean> {
  label: string;
}

export interface DropdownProps extends FieldProps<string> {
  children?: ReactNode;
}

export interface DropdownItemProps {
  value: string;
  title: string;
}

export function Form({ actions, children, ...props }: FormProps) {
  return host("form", props, actions, children);
}

Form.TextField = function TextField(props: TextFieldProps) {
  return host("form-field", { ...props, kind: "text" });
};

Form.TextArea = function TextArea(props: TextFieldProps) {
  return host("form-field", { ...props, kind: "textarea" });
};

Form.PasswordField = function PasswordField(props: TextFieldProps) {
  return host("form-field", { ...props, kind: "password" });
};

Form.Checkbox = function Checkbox(props: CheckboxProps) {
  return host("form-field", { ...props, kind: "checkbox" });
};

Form.Dropdown = Object.assign(
  function Dropdown({ children, ...props }: DropdownProps) {
    return host("form-field", { ...props, kind: "dropdown" }, children);
  },
  {
    Item: function DropdownItem(props: DropdownItemProps) {
      return host("form-option", props);
    },
  },
);

// MARK: - Actions

export interface ActionPanelProps {
  children?: ReactNode;
}

export interface ActionPanelSectionProps {
  title?: string;
  children?: ReactNode;
}

export function ActionPanel({ children }: ActionPanelProps) {
  return host("action-panel", {}, children);
}

ActionPanel.Section = function ActionPanelSection({ children, ...props }: ActionPanelSectionProps) {
  return host("action-panel-section", props, children);
};

export interface ActionProps {
  title: string;
  icon?: Icon;
  shortcut?: Shortcut;
  /** Destructive actions are drawn in red. */
  style?: "regular" | "destructive";
  onAction?: () => void | Promise<void>;
}

export function Action(props: ActionProps) {
  return host("action", props);
}

Action.CopyToClipboard = function CopyToClipboard(props: Omit<ActionProps, "title" | "onAction"> & {
  content: string;
  title?: string;
}) {
  const { content, title, ...rest } = props;
  return host("action", {
    icon: "doc.on.doc",
    ...rest,
    title: title ?? "Copy to Clipboard",
    onAction: () => Clipboard.copy(content).then(() => showHUD("Copied to Clipboard")),
  });
};

Action.Paste = function Paste(props: Omit<ActionProps, "title" | "onAction"> & { content: string; title?: string }) {
  const { content, title, ...rest } = props;
  return host("action", {
    icon: "doc.on.clipboard",
    ...rest,
    title: title ?? "Paste",
    onAction: () => Clipboard.paste(content),
  });
};

Action.OpenInBrowser = function OpenInBrowser(props: Omit<ActionProps, "title" | "onAction"> & {
  url: string;
  title?: string;
}) {
  const { url, title, ...rest } = props;
  return host("action", {
    icon: "safari",
    ...rest,
    title: title ?? "Open in Browser",
    onAction: () => open(url).then(closeMainWindow),
  });
};

Action.Push = function Push(props: Omit<ActionProps, "onAction"> & { target: ReactElement }) {
  const { target, ...rest } = props;
  const { push } = useNavigation();
  return host("action", { icon: "arrow.right", ...rest, onAction: () => push(target) });
};

Action.SubmitForm = function SubmitForm(props: Omit<ActionProps, "title" | "onAction"> & {
  title?: string;
  onSubmit: (values: FormValues) => void | Promise<void>;
}) {
  const { onSubmit, title, ...rest } = props;
  // Whippet keeps the fields' values and passes them to the handler of an action marked `submitsForm`.
  return host("action", {
    icon: "checkmark",
    ...rest,
    title: title ?? "Submit",
    submitsForm: true,
    onAction: onSubmit,
  });
};

// MARK: - Navigation

export interface Navigation {
  /** Shows another view on top of this one. Escape goes back. */
  push(view: ReactElement): void;
  pop(): void;
}

const NavigationContext = createContext<Navigation>({ push: () => {}, pop: () => {} });

export function useNavigation(): Navigation {
  return useContext(NavigationContext);
}

/** Lets Whippet pop the stack from outside React, on Escape. */
export interface NavigationController {
  pop(): boolean;
  popToRoot(): void;
}

/** Every view in the stack stays mounted, each in its own `view`, so going back keeps its state. */
export function NavigationRoot({ initial, controller }: { initial: ReactElement; controller: (c: NavigationController) => void }) {
  const [stack, setStack] = useState<ReactElement[]>([initial]);
  const navigation = useMemo<Navigation>(
    () => ({
      push: (view) => setStack((current) => [...current, view]),
      pop: () => setStack((current) => (current.length > 1 ? current.slice(0, -1) : current)),
    }),
    [],
  );
  controller({
    pop: () => {
      if (stack.length <= 1) return false;
      navigation.pop();
      return true;
    },
    popToRoot: () => setStack((current) => current.slice(0, 1)),
  });
  return createElement(
    NavigationContext.Provider,
    { value: navigation },
    stack.map((view, index) =>
      createElement(ErrorBoundary, { key: index }, host("view", { depth: index + 1 }, view)),
    ),
  );
}

/** Shows an error in place of a view that threw while rendering, rather than leaving the panel empty. */
class ErrorBoundary extends Component<{ children?: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error(error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const markdown = `## Something went wrong\n\n${error.message}\n\n\`\`\`\n${error.stack ?? ""}\n\`\`\``;
    return host("view", { depth: 0 }, host("detail", { markdown }));
  }
}

// MARK: - Functions

export interface ToastOptions {
  title: string;
  message?: string;
  style?: "success" | "failure";
}

/** Shows a short message over the screen, whether or not the panel is open. */
export async function showToast(options: ToastOptions | string): Promise<void> {
  await call("toast", typeof options === "string" ? { title: options } : options);
}

/** Closes the panel and shows a short message. */
export async function showHUD(title: string): Promise<void> {
  await closeMainWindow();
  await showToast({ title, style: "success" });
}

/** Closes Whippet's panel, returning to the app it opened over. */
export async function closeMainWindow(): Promise<void> {
  await call("closeMainWindow");
}

/** Goes back to the first view of the command. */
export async function popToRoot(): Promise<void> {
  await call("popToRoot");
}

/** Opens a URL in its default app. */
export async function open(url: string): Promise<void> {
  await call("open", { url });
}

export const Clipboard = {
  copy: async (text: string): Promise<void> => {
    await call("clipboard.copy", { text });
  },
  /** Closes the panel and pastes into the app it opened over. */
  paste: async (text: string): Promise<void> => {
    await call("clipboard.paste", { text });
  },
  /** Needs the `clipboard` permission in the manifest. */
  readText: (): Promise<string | undefined> => call<string | null>("clipboard.read").then((text) => text ?? undefined),
};

/** A small store of strings kept for the extension between launches. */
export const LocalStorage = {
  getItem: (key: string): Promise<string | undefined> =>
    call<string | null>("storage.get", { key }).then((value) => value ?? undefined),
  setItem: async (key: string, value: string): Promise<void> => {
    await call("storage.set", { key, value: String(value) });
  },
  removeItem: async (key: string): Promise<void> => {
    await call("storage.remove", { key });
  },
  allItems: (): Promise<Record<string, string>> => call<Record<string, string>>("storage.all"),
  clear: async (): Promise<void> => {
    await call("storage.clear");
  },
};

let preferences: Record<string, string | boolean> = {};

/** Sets the values from Settings › Extensions, when the runtime starts and whenever they change. */
export function setPreferences(values: Record<string, string | boolean>) {
  preferences = values;
}

/** The values the user set for the preferences the manifest declares. */
export function getPreferenceValues<T extends Record<string, string | boolean>>(): T {
  return { ...preferences } as T;
}

export interface Environment {
  extensionID: string;
  extensionName: string;
  /** The command launched most recently. */
  commandName: string;
  /** Whippet's version. */
  whippetVersion: string;
}

export const environment: Environment = {
  extensionID: "",
  extensionName: "",
  commandName: "",
  whippetVersion: "",
};

/** What a command receives: the text typed for its argument, keyed by the argument's name. */
export interface LaunchProps {
  arguments: Record<string, string>;
}

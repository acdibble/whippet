# Extensions

An extension adds commands to Whippet, written in TypeScript or JavaScript with React. A command can show a list, a
detail or a form, which Whippet draws natively, or run without a view, as for copying a generated value.

Extensions are a beta feature, off until Settings › General › Beta Features › Extensions is turned on. Until then
Whippet doesn't read the Extensions folder or run anything in it.

Extensions live in `~/Library/Application Support/Whippet/Extensions` (`Whippet Dev` for development builds), one folder
each. Whippet watches the folder, so an extension reloads as soon as it's rebuilt. A new extension stays off until it's
turned on in Settings › Extensions, which approves the access its manifest asks for.

## A first extension

```
hello/
  manifest.json
  src/index.tsx
  index.js        (built from src/index.tsx)
```

`manifest.json`:

```json
{
  "id": "com.example.hello",
  "name": "Hello",
  "version": "1.0.0",
  "apiVersion": 1,
  "icon": "hand.wave",
  "commands": [
    { "name": "BrowseFruit", "title": "Browse Fruit" },
    { "name": "copyUUID", "title": "Copy UUID", "mode": "no-view" }
  ]
}
```

`src/index.tsx` exports one function per command, named as in the manifest. A command with a view is a component, so
its name is capitalized; one without a view is a plain function.

```tsx
import { Action, ActionPanel, Clipboard, Detail, List, Route, Routes, showHUD, useNavigate, useParams } from "@whippet/api";

export function BrowseFruit() {
  return (
    <Routes>
      <Route path="/" element={<FruitList />} />
      <Route path="/fruit/:name" element={<FruitDetail />} />
    </Routes>
  );
}

function FruitList() {
  const navigate = useNavigate();
  return (
    <List>
      {["Apple", "Banana", "Cherry"].map((name) => (
        <List.Item
          key={name}
          title={name}
          actions={
            <ActionPanel>
              <Action title="Show Details" onAction={() => navigate(`/fruit/${name}`)} />
              <Action.CopyToClipboard content={name} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

function FruitDetail() {
  const { name } = useParams();
  return <Detail markdown={`# ${name}`} />;
}

export async function copyUUID() {
  await Clipboard.copy(crypto.randomUUID());
  await showHUD("Copied a UUID");
}
```

Build it into `index.js` with esbuild. React and `@whippet/api` are left out, because Whippet supplies them:

```sh
npx esbuild src/index.tsx --bundle --format=cjs --platform=neutral --target=safari18 --jsx=automatic \
  --external:react --external:react/jsx-runtime --external:@whippet/api --outfile=index.js
```

Add `--watch` while working on it; Whippet reloads the extension, and the open command, on each save. For types,
install React's (`npm install -D react@19.3.1 @types/react`) and point `@whippet/api` at `Extensions/api` in this
repository, whose `npm run build` writes its declarations to `dist/`.

The examples in `Extensions/examples` build with `npm run build:examples` in `Extensions/api`: `hello` shows each
kind of view and command, and `github` searches GitHub's API as you type.

## The manifest

| Key | | |
|---|---|---|
| `id` | required | Reverse-DNS, such as `com.example.github`. Hotkeys, approvals and storage are kept under it. |
| `name`, `version` | required | |
| `apiVersion` | required | `1`. Whippet refuses an extension written for an API version it doesn't have. |
| `description`, `author` | | Shown in Settings › Extensions. |
| `icon` | | An SF Symbol name, an emoji or an image file in the extension's folder. |
| `permissions` | | `network`: hosts `fetch` may reach, such as `api.github.com`, `*.example.com` or `*` for any. `clipboard`: `true` to read the clipboard. |
| `preferences` | | Settings the user fills in: `name`, `title`, `type` (`text`, `secret` or `checkbox`), `description`, `placeholder`, `required` and `default`. Secrets are kept in the Keychain. A command whose required preferences are empty opens Settings instead of running. |
| `commands` | required | `name` (the export: a component for a view, capitalized, or a function), `title`, `subtitle`, `icon`, `mode` (`view`, the default, or `no-view`) and `argument` (`{ "name", "placeholder" }`, typed after Tab). |

## The API

Everything is imported from `@whippet/api`, and hooks from `react`.

### Views

- **`List`**: `List.Item` (`title`, `subtitle`, `icon`, `accessories`, `keywords`, `actions`) and `List.Section`.
  Whippet filters the items by title, subtitle and keywords as the user types. A list with `onSearchTextChange` searches
  for itself instead; add `throttle` to wait until typing pauses, as for a search that goes over the network.
  `isLoading` shows a spinner.
- **`Detail`**: Markdown (`markdown`), with headings, lists, quotes, code and links.
- **`Form`**: `Form.TextField`, `Form.TextArea`, `Form.PasswordField`, `Form.Checkbox` and `Form.Dropdown` with
  `Form.Dropdown.Item`. Each field has an `id`; `Action.SubmitForm` receives the values keyed by it.

Each view takes `actions`, an `ActionPanel` of actions. The first runs on Return, the second on ⌘Return, and all of them
are in the ⌘K menu. In a form, Return in a text field and ⌘Return both run the first. An action's `shortcut`, such as
`{ modifiers: ["cmd"], key: "o" }`, needs ⌘ or ⌃.

### Actions

`Action` (`title`, `icon`, `shortcut`, `style: "destructive"`, `onAction`), `Action.CopyToClipboard`, `Action.Paste`,
`Action.OpenInBrowser` and `Action.SubmitForm`. `ActionPanel.Section` groups actions under a title in the menu.

### Navigation

A command has a URL and a history, in the manner of react-router. It starts at `/`, and its component stays mounted as
it navigates, so state kept there lasts; what changes is what it renders.

- `useNavigate()` returns `navigate(to, { state, replace })`, and `navigate(-1)` to go back. A path without a leading
  slash is relative to the current one.
- `<Routes>` renders the first `<Route path element>` that matches, and `useParams()` reads its `:name` segments.
- `useLocation()` returns `pathname` and the `state` passed to `navigate`. A command can render from these directly,
  without `<Routes>`, such as showing a note when `state` holds one:

  ```tsx
  const { state: note } = useLocation<Note | undefined>();
  if (note) return <Detail markdown={note.body} />;
  ```

Escape goes back through the history, and leaves the command from its first entry. Going back restores the search text
and the selected item of the page returned to.

### Functions

| | |
|---|---|
| `showToast({ title, message, style })`, `showHUD(title)` | A message over the screen. `showHUD` closes the panel first. |
| `closeMainWindow()` | |
| `popToRoot()` | Goes back to the command's first entry. |
| `open(url)` | Opens a web or app link. File URLs aren't allowed. |
| `Clipboard.copy(text)`, `Clipboard.paste(text)`, `Clipboard.readText()` | Pasting closes the panel and pastes into the app it opened over. Reading needs the `clipboard` permission. |
| `LocalStorage` | `getItem`, `setItem`, `removeItem`, `allItems` and `clear`: strings kept for the extension between launches. |
| `getPreferenceValues()` | The values of the manifest's preferences. |
| `environment` | `extensionID`, `extensionName`, `commandName` and `whippetVersion`. |

A command receives `{ arguments }`, with the text typed for its argument under the argument's name.

### What's available

Each extension runs in its own JavaScriptCore context, with nothing but JavaScript and what Whippet adds: `console`,
`setTimeout`, `setInterval`, `queueMicrotask`, `fetch` (text bodies, to the manifest's hosts only, redirects included),
`Headers`, `Response`, `URLSearchParams` and `crypto.randomUUID`. There's no file system, no processes and no Node
modules; an extension can only `require` React and `@whippet/api`. What it logs is in Settings › Extensions › View Log.

## How it works

Whippet's runtime (`Extensions/api`) is React with a custom renderer, from `react-reconciler`. Its host elements are
plain objects. After each commit, a command's view is serialized to JSON and sent to Swift, with each function in its
props replaced by an id, and with the length of its history and the key of the entry shown, so Whippet can tell going
forward from going back. `ExtensionRuntime` (in WhippetCore) parses it into an
`ExtensionView`, which the launcher draws, and sends ids back when the user acts. Messages both ways are JSON, so the
runtime could move into a separate process later.

The runtime is bundled, with React in production mode, into
`Packages/WhippetCore/Sources/WhippetCore/Resources/ExtensionRuntime.js` and committed, so building Whippet needs no
Node. After changing anything in `Extensions/api/src`, run `npm install` and `npm run build` there and commit the bundle;
CI checks that it's up to date.

### Known limits

- Extensions run in Whippet's process. JavaScriptCore has no public way to interrupt a script, so one stuck in a loop
  keeps its own thread busy until Whippet quits, though the panel stays responsive.
- Extensions aren't synced to other Macs, and there's no catalogue or automatic updates yet.

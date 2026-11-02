import {
  Action,
  ActionPanel,
  Clipboard,
  Detail,
  Form,
  List,
  LocalStorage,
  Route,
  Routes,
  showHUD,
  showToast,
  useLocation,
  useNavigate,
  useParams,
} from "@whippet/api";
import type { FormValues, LaunchProps } from "@whippet/api";
import { useEffect, useState } from "react";

const allFruit = [
  { name: "Apple", emoji: "🍎", colour: "Red or green", season: "Autumn" },
  { name: "Banana", emoji: "🍌", colour: "Yellow", season: "All year" },
  { name: "Cherry", emoji: "🍒", colour: "Red", season: "Summer" },
  { name: "Grapes", emoji: "🍇", colour: "Purple or green", season: "Late summer" },
  { name: "Lemon", emoji: "🍋", colour: "Yellow", season: "Winter" },
];

/** URL routing: each page is a route, and its URL says which fruit to show. Escape goes back. */
export function BrowseFruit() {
  return (
    <Routes>
      <Route path="/" element={<FruitList />} />
      <Route path="/fruit/:name" element={<FruitDetail />} />
    </Routes>
  );
}

/** A list Whippet filters by itself. */
function FruitList() {
  const navigate = useNavigate();
  return (
    <List searchBarPlaceholder="Search fruit…">
      <List.Section title="Fruit">
        {allFruit.map((fruit) => (
          <List.Item
            key={fruit.name}
            id={fruit.name}
            title={fruit.name}
            subtitle={fruit.colour}
            icon={fruit.emoji}
            keywords={[fruit.season]}
            accessories={[{ text: fruit.season, icon: "calendar" }]}
            actions={
              <ActionPanel>
                <Action title="Show Details" icon="info.circle" onAction={() => navigate(`/fruit/${fruit.name}`)} />
                <Action.CopyToClipboard content={`${fruit.emoji} ${fruit.name}`} />
                <Action.Paste content={fruit.name} shortcut={{ modifiers: ["cmd", "shift"], key: "v" }} />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}

function FruitDetail() {
  const { name } = useParams<{ name: string }>();
  const fruit = allFruit.find((candidate) => candidate.name === name);
  if (!fruit) return <Detail markdown={`# No fruit called ${name}`} />;
  const markdown = [
    `# ${fruit.emoji} ${fruit.name}`,
    `**Colour:** ${fruit.colour}`,
    `**In season:** ${fruit.season}`,
    "## Ways to eat it",
    "- Fresh\n- In a crumble\n- With `yoghurt`",
    "> Detail views take Markdown: headings, lists, quotes and code.",
  ].join("\n\n");
  return (
    <Detail
      navigationTitle={fruit.name}
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy Name" content={fruit.name} />
          <Action.OpenInBrowser url={`https://en.wikipedia.org/wiki/${fruit.name}`} />
        </ActionPanel>
      }
    />
  );
}

interface Note {
  id: string;
  title: string;
  body: string;
}

async function loadNotes(): Promise<Note[]> {
  return JSON.parse((await LocalStorage.getItem("notes")) ?? "[]");
}

async function saveNotes(notes: Note[]) {
  await LocalStorage.setItem("notes", JSON.stringify(notes));
}

/**
 * Conditional rendering: the command keeps the notes, and what it shows follows the location. Opening a note navigates
 * with the note as its state, and the form has a path of its own. Escape goes back either way.
 */
export function Notes() {
  const navigate = useNavigate();
  const { pathname, state: openNote } = useLocation<Note | undefined>();
  const [notes, setNotes] = useState<Note[] | null>(null);

  const reload = () => loadNotes().then(setNotes);
  useEffect(() => {
    reload();
  }, []);

  const remove = async (note: Note) => {
    const remaining = (notes ?? []).filter((item) => item.id !== note.id);
    await saveNotes(remaining);
    setNotes(remaining);
    await showToast({ title: "Deleted", message: note.title });
  };

  if (pathname === "/new") {
    return (
      <NoteForm
        onSave={() => {
          reload();
          navigate(-1);
        }}
      />
    );
  }

  if (openNote) {
    return (
      <Detail
        navigationTitle={openNote.title}
        markdown={`# ${openNote.title}\n\n${openNote.body}`}
        actions={
          <ActionPanel>
            <Action.CopyToClipboard content={openNote.body} />
          </ActionPanel>
        }
      />
    );
  }

  const newNote = (
    <Action title="New Note" icon="plus" shortcut={{ modifiers: ["cmd"], key: "n" }} onAction={() => navigate("/new")} />
  );

  return (
    <List isLoading={notes === null} searchBarPlaceholder="Search notes…" actions={<ActionPanel>{newNote}</ActionPanel>}>
      {(notes ?? []).map((note) => (
        <List.Item
          key={note.id}
          id={note.id}
          title={note.title}
          subtitle={note.body.split("\n")[0]}
          icon="note.text"
          actions={
            <ActionPanel>
              <Action title="Open" icon="doc.text" onAction={() => navigate("/note", { state: note })} />
              <Action.CopyToClipboard content={note.body} />
              {newNote}
              <ActionPanel.Section title="Danger">
                <Action
                  title="Delete Note"
                  icon="trash"
                  style="destructive"
                  shortcut={{ modifiers: ["ctrl"], key: "x" }}
                  onAction={() => remove(note)}
                />
              </ActionPanel.Section>
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

function NoteForm({ onSave }: { onSave: () => void }) {
  const [titleError, setTitleError] = useState(false);

  const submit = async (values: FormValues) => {
    const title = String(values.title ?? "").trim();
    if (!title) {
      setTitleError(true);
      await showToast({ title: "A note needs a title", style: "failure" });
      return;
    }
    const notes = await loadNotes();
    const body = String(values.body ?? "");
    notes.unshift({ id: crypto.randomUUID(), title, body: values.important ? `**Important.** ${body}` : body });
    await saveNotes(notes);
    await showToast({ title: "Saved", message: title, style: "success" });
    onSave();
  };

  return (
    <Form
      navigationTitle="New Note"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Save Note" onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.TextField id="title" title={titleError ? "Title (required)" : "Title"} placeholder="Shopping" />
      <Form.TextArea id="body" title="Note" placeholder="Milk, eggs, flour" />
      <Form.Dropdown id="folder" title="Folder" defaultValue="personal">
        <Form.Dropdown.Item value="personal" title="Personal" />
        <Form.Dropdown.Item value="work" title="Work" />
      </Form.Dropdown>
      <Form.Checkbox id="important" title="" label="Important" />
    </Form>
  );
}

/** A form as a command of its own, which closes once the note is saved. */
export function AddNote() {
  return <NoteForm onSave={() => showHUD("Saved the note")} />;
}

/** A command without a view: a plain function, which runs, then the panel closes. */
export async function copyUUID() {
  await Clipboard.copy(crypto.randomUUID());
  await showHUD("Copied a UUID");
}

/** A command without a view that takes an argument, typed after Tab. */
export async function greet({ arguments: args }: LaunchProps) {
  await showHUD(`Hello, ${args.name || "world"}!`);
}

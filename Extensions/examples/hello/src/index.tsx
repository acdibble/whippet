import { Action, ActionPanel, Clipboard, Detail, Form, List, LocalStorage, showHUD, showToast, useNavigation } from "@whippet/api";
import type { FormValues, LaunchProps } from "@whippet/api";
import { useEffect, useState } from "react";

const allFruit = [
  { name: "Apple", emoji: "🍎", colour: "Red or green", season: "Autumn" },
  { name: "Banana", emoji: "🍌", colour: "Yellow", season: "All year" },
  { name: "Cherry", emoji: "🍒", colour: "Red", season: "Summer" },
  { name: "Grapes", emoji: "🍇", colour: "Purple or green", season: "Late summer" },
  { name: "Lemon", emoji: "🍋", colour: "Yellow", season: "Winter" },
];

/** A list Whippet filters by itself, with a detail pushed from each item. */
export function fruit() {
  return (
    <List searchBarPlaceholder="Search fruit…">
      <List.Section title="Fruit">
        {allFruit.map((item) => (
          <List.Item
            key={item.name}
            id={item.name}
            title={item.name}
            subtitle={item.colour}
            icon={item.emoji}
            keywords={[item.season]}
            accessories={[{ text: item.season, icon: "calendar" }]}
            actions={
              <ActionPanel>
                <Action.Push title="Show Details" target={<FruitDetail name={item.name} />} />
                <Action.CopyToClipboard content={`${item.emoji} ${item.name}`} />
                <Action.Paste content={item.name} shortcut={{ modifiers: ["cmd", "shift"], key: "v" }} />
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}

function FruitDetail({ name }: { name: string }) {
  const item = allFruit.find((candidate) => candidate.name === name)!;
  const markdown = [
    `# ${item.emoji} ${item.name}`,
    `**Colour:** ${item.colour}`,
    `**In season:** ${item.season}`,
    "## Ways to eat it",
    "- Fresh\n- In a crumble\n- With `yoghurt`",
    "> Detail views take Markdown: headings, lists, quotes and code.",
  ].join("\n\n");
  return (
    <Detail
      navigationTitle={item.name}
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy Name" content={item.name} />
          <Action.OpenInBrowser url={`https://en.wikipedia.org/wiki/${item.name}`} />
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

/** A list of notes kept in LocalStorage, with a form pushed to add one. */
export function notes() {
  const [items, setItems] = useState<Note[] | null>(null);

  const reload = () => loadNotes().then(setItems);
  useEffect(() => {
    reload();
  }, []);

  const remove = async (note: Note) => {
    const remaining = (items ?? []).filter((item) => item.id !== note.id);
    await saveNotes(remaining);
    setItems(remaining);
    await showToast({ title: "Deleted", message: note.title });
  };

  const newNote = <Action.Push title="New Note" icon="plus" shortcut={{ modifiers: ["cmd"], key: "n" }} target={<NoteForm onSave={reload} />} />;

  return (
    <List
      isLoading={items === null}
      searchBarPlaceholder="Search notes…"
      actions={<ActionPanel>{newNote}</ActionPanel>}
    >
      {(items ?? []).map((note) => (
        <List.Item
          key={note.id}
          id={note.id}
          title={note.title}
          subtitle={note.body.split("\n")[0]}
          icon="note.text"
          actions={
            <ActionPanel>
              <Action.Push title="Open" target={<Detail navigationTitle={note.title} markdown={`# ${note.title}\n\n${note.body}`} />} />
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

function NoteForm({ onSave }: { onSave?: () => void }) {
  const { pop } = useNavigation();
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
    onSave?.();
    pop();
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

/** A form as a command of its own. */
export function addNote() {
  return <NoteForm />;
}

/** A command without a view: it runs, then the panel closes. */
export async function copyUUID() {
  await Clipboard.copy(crypto.randomUUID());
  await showHUD("Copied a UUID");
}

/** A command without a view that takes an argument, typed after Tab. */
export async function greet({ arguments: args }: LaunchProps) {
  await showHUD(`Hello, ${args.name || "world"}!`);
}

import { Action, ActionPanel, List, getPreferenceValues, showToast } from "@whippet/api";
import { useEffect, useState } from "react";

interface Repository {
  id: number;
  full_name: string;
  description: string | null;
  html_url: string;
  clone_url: string;
  stargazers_count: number;
  language: string | null;
}

/** A list that searches for itself as you type, waiting for typing to pause since each search is a request. */
export function searchRepositories() {
  const [query, setQuery] = useState("");
  const [repositories, setRepositories] = useState<Repository[]>([]);
  const [isLoading, setLoading] = useState(false);

  useEffect(() => {
    if (!query.trim()) {
      setRepositories([]);
      return;
    }
    let cancelled = false;
    setLoading(true);
    const { token } = getPreferenceValues<{ token: string }>();
    fetch(`https://api.github.com/search/repositories?per_page=20&q=${encodeURIComponent(query)}`, {
      headers: { Accept: "application/vnd.github+json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
        const json = await response.json();
        if (!cancelled) setRepositories(json.items);
      })
      .catch((error) => showToast({ title: "Search failed", message: error.message, style: "failure" }))
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [query]);

  return (
    <List isLoading={isLoading} onSearchTextChange={setQuery} throttle searchBarPlaceholder="Search repositories…">
      {repositories.map((repository) => (
        <List.Item
          key={repository.id}
          id={String(repository.id)}
          title={repository.full_name}
          subtitle={repository.description ?? undefined}
          icon="book.closed"
          accessories={[
            ...(repository.language ? [{ text: repository.language }] : []),
            { text: repository.stargazers_count.toLocaleString(), icon: "star" },
          ]}
          actions={
            <ActionPanel>
              <Action.OpenInBrowser url={repository.html_url} />
              <Action.CopyToClipboard title="Copy Clone URL" content={repository.clone_url} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

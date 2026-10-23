# Tickets

Each ticket is a Markdown file. Its folder is its status:

| Folder     | Meaning                         |
| ---------- | ------------------------------- |
| `backlog/` | Ideas, not committed to yet     |
| `todo/`    | Agreed and ready to start       |
| `doing/`   | In progress                     |
| `done/`    | Finished                        |

## Files

Name tickets `<id>-<slug>.md`, for example `0003-paste-to-app.md`. IDs are four digits, never reused, and the next one is the highest ID in any folder plus one. `./new.sh "Title"` creates a backlog ticket with the next ID and prints its path.

Change status by moving the file, so git history records when it happened:

```sh
git mv tickets/todo/0003-paste-to-app.md tickets/doing/
```

## Format

```markdown
---
priority: high        # high | medium | low
labels: [clipboard]
---

# Title

What and why, in a few sentences.

## Done when

- [ ] An observable outcome

## Notes

Anything learned along the way.
```

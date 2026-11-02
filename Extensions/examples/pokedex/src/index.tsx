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
  getPreferenceValues,
  showHUD,
  showToast,
  useNavigate,
  useParams,
} from "@whippet/api";
import type { FormValues, LaunchProps } from "@whippet/api";
import { useEffect, useState } from "react";
import {
  LAST_NUMBER,
  TYPES,
  artwork,
  bulbapedia,
  displayName,
  english,
  idFromURL,
  loadEvolutions,
  loadIndex,
  loadPokemon,
  loadSpecies,
  loadType,
  pokedexNumber,
  speciesName,
  sprite,
  type ChainLink,
  type Entry,
} from "./pokeapi";

// MARK: - Hooks

interface Loaded<T> {
  data?: T;
  error?: Error;
  isLoading: boolean;
}

/** Loads something when the component mounts and whenever `key` changes, ignoring answers that arrive too late. */
function useLoad<T>(load: () => Promise<T>, key: unknown): Loaded<T> {
  const [state, setState] = useState<Loaded<T>>({ isLoading: true });
  useEffect(() => {
    let isCurrent = true;
    setState((current) => ({ ...current, isLoading: true }));
    load().then(
      (data) => isCurrent && setState({ data, isLoading: false }),
      (error: Error) => isCurrent && setState({ error, isLoading: false }),
    );
    return () => {
      isCurrent = false;
    };
  }, [key]);
  return state;
}

interface Favourites {
  has(name: string): boolean;
  toggle(name: string): void;
}

/** Favourite Pokémon, kept in LocalStorage. Held by each command's component, which stays mounted as it navigates. */
function useFavourites(): Favourites {
  const [names, setNames] = useState<string[]>([]);
  useEffect(() => {
    LocalStorage.getItem("favourites").then((saved) => saved && setNames(JSON.parse(saved)));
  }, []);
  return {
    has: (name) => names.includes(name),
    toggle: (name) => {
      const isFavourite = names.includes(name);
      const updated = isFavourite ? names.filter((other) => other !== name) : [...names, name];
      setNames(updated);
      LocalStorage.setItem("favourites", JSON.stringify(updated));
      showToast({ title: isFavourite ? "Removed from Favourites" : "Added to Favourites", message: displayName(name) });
    },
  };
}

function useShiny() {
  return getPreferenceValues<{ shiny: boolean }>().shiny;
}

// MARK: - Routes

/** The pages every command shares, after its own first page. */
function pokemonRoutes(favourites: Favourites) {
  return [
    <Route key="pokemon" path="/pokemon/:name" element={<PokemonDetail favourites={favourites} />} />,
    <Route key="evolutions" path="/pokemon/:name/evolutions" element={<Evolutions />} />,
  ];
}

/** Every Pokémon, with favourites first. Whippet filters them by name and number as you type. */
export function Pokedex() {
  const favourites = useFavourites();
  return (
    <Routes>
      <Route path="/" element={<PokemonList favourites={favourites} />} />
      {pokemonRoutes(favourites)}
    </Routes>
  );
}

/** A form to choose a type, then the Pokémon of that type. */
export function PokemonByType() {
  const favourites = useFavourites();
  return (
    <Routes>
      <Route path="/" element={<TypeForm />} />
      <Route path="/type/:type" element={<TypeList favourites={favourites} />} />
      {pokemonRoutes(favourites)}
    </Routes>
  );
}

/** A random Pokémon's page. ⌘R picks another, in its place. */
export function RandomPokemon() {
  const favourites = useFavourites();
  const [first] = useState(randomNumber);
  return (
    <Routes>
      <Route path="/" element={<PokemonDetail favourites={favourites} number={first} random />} />
      {pokemonRoutes(favourites)}
    </Routes>
  );
}

/** Copies the name of the Pokémon with the number typed after Tab, without opening a view. */
export async function copyPokemonName({ arguments: args }: LaunchProps) {
  const number = Number(args.number);
  if (!Number.isInteger(number) || number < 1 || number > LAST_NUMBER) {
    await showToast({ title: `Pokédex numbers go from 1 to ${LAST_NUMBER}`, style: "failure" });
    return;
  }
  const name = await speciesName(number);
  await Clipboard.copy(name);
  await showHUD(`Copied ${name}`);
}

function randomNumber() {
  return 1 + Math.floor(Math.random() * LAST_NUMBER);
}

// MARK: - Lists

function PokemonList({ favourites }: { favourites: Favourites }) {
  const index = useLoad(loadIndex, "index");
  const entries = index.data ?? [];
  const favouriteEntries = entries.filter((entry) => favourites.has(entry.name));
  return (
    <List isLoading={index.isLoading} searchBarPlaceholder="Search by name or number…">
      {index.error && <List.Item title="Couldn't load the Pokédex" subtitle={index.error.message} icon="exclamationmark.triangle" />}
      {favouriteEntries.length > 0 && (
        <List.Section title="Favourites">
          {favouriteEntries.map((entry) => (
            <PokemonItem key={entry.name} entry={entry} favourites={favourites} id={`favourite-${entry.name}`} />
          ))}
        </List.Section>
      )}
      <List.Section title="All Pokémon">
        {entries.map((entry) => (
          <PokemonItem key={entry.name} entry={entry} favourites={favourites} />
        ))}
      </List.Section>
    </List>
  );
}

function TypeList({ favourites }: { favourites: Favourites }) {
  const { type } = useParams<{ type: string }>();
  const pokemon = useLoad(() => loadType(type), type);
  return (
    <List
      isLoading={pokemon.isLoading}
      navigationTitle={`${displayName(type)} Pokémon`}
      searchBarPlaceholder={`Search ${displayName(type)} Pokémon…`}
    >
      {pokemon.error && <List.Item title="Couldn't load the type" subtitle={pokemon.error.message} icon="exclamationmark.triangle" />}
      {(pokemon.data ?? []).map((entry) => (
        <PokemonItem key={entry.name} entry={entry} favourites={favourites} />
      ))}
    </List>
  );
}

function PokemonItem({ entry, favourites, id }: { entry: Entry; favourites: Favourites; id?: string }) {
  const navigate = useNavigate();
  const shiny = useShiny();
  const isFavourite = favourites.has(entry.name);
  return (
    <List.Item
      id={id ?? entry.name}
      title={displayName(entry.name)}
      icon={sprite(entry.id, shiny)}
      keywords={[String(entry.id), entry.name]}
      accessories={[...(isFavourite ? [{ icon: "star.fill" }] : []), { text: pokedexNumber(entry.id) }]}
      actions={
        <ActionPanel>
          <Action title="Show Details" icon="info.circle" onAction={() => navigate(`/pokemon/${entry.name}`)} />
          <Action
            title="Show Evolutions"
            icon="arrow.triangle.branch"
            shortcut={{ modifiers: ["cmd"], key: "e" }}
            onAction={() => navigate(`/pokemon/${entry.name}/evolutions`)}
          />
          <Action
            title={isFavourite ? "Remove from Favourites" : "Add to Favourites"}
            icon={isFavourite ? "star.slash" : "star"}
            shortcut={{ modifiers: ["cmd"], key: "f" }}
            onAction={() => favourites.toggle(entry.name)}
          />
          <ActionPanel.Section title="Share">
            <Action.CopyToClipboard
              title="Copy Name"
              content={displayName(entry.name)}
              shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
            />
            <Action.OpenInBrowser title="Open on Bulbapedia" url={bulbapedia(entry.name)} />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}

// MARK: - Details

const STAT_NAMES: Record<string, string> = {
  hp: "HP",
  attack: "Attack",
  defense: "Defense",
  "special-attack": "Sp. Atk",
  "special-defense": "Sp. Def",
  speed: "Speed",
};

/** A bar of up to 20 blocks, out of the highest base stat, 255. */
function bar(value: number) {
  return "█".repeat(Math.max(1, Math.round((value / 255) * 20)));
}

function PokemonDetail({ favourites, number, random }: { favourites: Favourites; number?: number; random?: boolean }) {
  const params = useParams<{ name: string }>();
  const navigate = useNavigate();
  const shiny = useShiny();
  const nameOrNumber = number ?? params.name;
  const loaded = useLoad(async () => {
    const pokemon = await loadPokemon(nameOrNumber);
    return { pokemon, species: await loadSpecies(pokemon) };
  }, nameOrNumber);

  if (loaded.error) {
    return <Detail markdown={`# Couldn't load ${nameOrNumber}\n\n${loaded.error.message}`} />;
  }
  if (!loaded.data) {
    return <Detail isLoading markdown="" />;
  }

  const { pokemon, species } = loaded.data;
  const name = english(species.names)?.name ?? displayName(pokemon.name);
  const genus = english(species.genera)?.genus;
  const flavour = english([...species.flavor_text_entries].reverse())?.flavor_text.replace(/\s+/g, " ");
  const types = pokemon.types.map(({ type }) => displayName(type.name)).join(" / ");
  const abilities = pokemon.abilities
    .map(({ ability, is_hidden }) => `- ${displayName(ability.name)}${is_hidden ? " *(hidden)*" : ""}`)
    .join("\n");
  const total = pokemon.stats.reduce((sum, stat) => sum + stat.base_stat, 0);
  const stats = pokemon.stats
    .map(({ stat, base_stat }) => `${(STAT_NAMES[stat.name] ?? stat.name).padEnd(8)} ${String(base_stat).padStart(3)}  ${bar(base_stat)}`)
    .join("\n");
  const markdown = [
    `# ${name} ${pokedexNumber(pokemon.id)}`,
    `![${name}](${artwork(pokemon.id, shiny)})`,
    genus && `*${genus}*`,
    flavour && `> ${flavour}`,
    `**Type:** ${types} · **Height:** ${(pokemon.height / 10).toFixed(1)} m · **Weight:** ${(pokemon.weight / 10).toFixed(1)} kg`,
    `## Abilities\n\n${abilities}`,
    `## Base Stats\n\n\`\`\`\n${stats}\n${"Total".padEnd(8)} ${String(total).padStart(3)}\n\`\`\``,
  ]
    .filter(Boolean)
    .join("\n\n");

  const isFavourite = favourites.has(pokemon.name);
  // Next and previous replace this page rather than adding to the history, so Escape still goes back to the list.
  const goTo = (id: number) => navigate(`/pokemon/${id}`, { replace: true });
  return (
    <Detail
      navigationTitle={name}
      isLoading={loaded.isLoading}
      markdown={markdown}
      actions={
        <ActionPanel>
          <Action
            title="Show Evolutions"
            icon="arrow.triangle.branch"
            shortcut={{ modifiers: ["cmd"], key: "e" }}
            onAction={() => navigate(`/pokemon/${pokemon.name}/evolutions`)}
          />
          <Action
            title={isFavourite ? "Remove from Favourites" : "Add to Favourites"}
            icon={isFavourite ? "star.slash" : "star"}
            shortcut={{ modifiers: ["cmd"], key: "f" }}
            onAction={() => favourites.toggle(pokemon.name)}
          />
          <ActionPanel.Section title="Browse">
            {random && (
              <Action
                title="Another Random Pokémon"
                icon="dice"
                shortcut={{ modifiers: ["cmd"], key: "r" }}
                onAction={() => goTo(randomNumber())}
              />
            )}
            {pokemon.id < LAST_NUMBER && (
              <Action title="Next Pokémon" icon="chevron.right" shortcut={{ modifiers: ["cmd"], key: "]" }} onAction={() => goTo(pokemon.id + 1)} />
            )}
            {pokemon.id > 1 && (
              <Action title="Previous Pokémon" icon="chevron.left" shortcut={{ modifiers: ["cmd"], key: "[" }} onAction={() => goTo(pokemon.id - 1)} />
            )}
          </ActionPanel.Section>
          <ActionPanel.Section title="Share">
            <Action.CopyToClipboard title="Copy Name" content={name} shortcut={{ modifiers: ["cmd", "shift"], key: "c" }} />
            <Action.OpenInBrowser title="Open on Bulbapedia" url={bulbapedia(pokemon.name)} />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}

// MARK: - Evolutions

interface Stage {
  id: number;
  name: string;
  from?: string;
  how?: string;
}

/** How a Pokémon evolves, such as `Level 16` or `Use Thunder Stone`. */
function evolutionMethod(details: ChainLink["evolution_details"]) {
  const detail = details[0];
  if (!detail) return undefined;
  const parts: string[] = [];
  if (detail.trigger.name === "level-up") parts.push(detail.min_level ? `Level ${detail.min_level}` : "Level up");
  if (detail.trigger.name === "trade") parts.push("Trade");
  if (detail.item) parts.push(`Use ${displayName(detail.item.name)}`);
  if (detail.held_item) parts.push(`holding ${displayName(detail.held_item.name)}`);
  if (detail.min_happiness) parts.push("with high friendship");
  if (detail.known_move) parts.push(`knowing ${displayName(detail.known_move.name)}`);
  if (detail.time_of_day) parts.push(`at ${detail.time_of_day}`);
  return parts.length > 0 ? parts.join(" ") : displayName(detail.trigger.name);
}

function stages(link: ChainLink, from?: string): Stage[] {
  const stage: Stage = {
    id: idFromURL(link.species.url),
    name: link.species.name,
    from,
    how: evolutionMethod(link.evolution_details),
  };
  return [stage, ...link.evolves_to.flatMap((next) => stages(next, link.species.name))];
}

function Evolutions() {
  const { name } = useParams<{ name: string }>();
  const navigate = useNavigate();
  const shiny = useShiny();
  const chain = useLoad(async () => stages(await loadEvolutions(await loadPokemon(name))), name);
  return (
    <List isLoading={chain.isLoading} navigationTitle={`${displayName(name)} Evolutions`}>
      {chain.error && <List.Item title="Couldn't load the evolutions" subtitle={chain.error.message} icon="exclamationmark.triangle" />}
      {(chain.data ?? []).map((stage) => (
        <List.Item
          key={stage.name}
          id={stage.name}
          title={displayName(stage.name)}
          subtitle={stage.from ? `from ${displayName(stage.from)}` : "Base form"}
          icon={sprite(stage.id, shiny)}
          accessories={[...(stage.how ? [{ text: stage.how }] : []), { text: pokedexNumber(stage.id) }]}
          actions={
            <ActionPanel>
              <Action title="Show Details" icon="info.circle" onAction={() => navigate(`/pokemon/${stage.id}`)} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}

// MARK: - Types

function TypeForm() {
  const navigate = useNavigate();
  return (
    <Form
      navigationTitle="Find Pokémon by Type"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Show Pokémon" onSubmit={(values: FormValues) => navigate(`/type/${values.type}`)} />
        </ActionPanel>
      }
    >
      <Form.Dropdown id="type" title="Type" defaultValue="electric">
        {TYPES.map((type) => (
          <Form.Dropdown.Item key={type} value={type} title={displayName(type)} />
        ))}
      </Form.Dropdown>
    </Form>
  );
}

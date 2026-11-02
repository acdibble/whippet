// PokéAPI (https://pokeapi.co), its sprites, and the few pieces of each response the Pokédex shows.
import { LocalStorage } from "@whippet/api";

const API = "https://pokeapi.co/api/v2";
const SPRITES = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon";

/** The last Pokémon in the National Pokédex. Numbers above it are alternate forms. */
export const LAST_NUMBER = 1025;

export const TYPES = [
  "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
  "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy",
];

export interface Entry {
  id: number;
  name: string;
}

interface NamedResource {
  name: string;
  url: string;
}

export interface Pokemon {
  id: number;
  name: string;
  /** In decimetres. */
  height: number;
  /** In hectograms. */
  weight: number;
  types: { slot: number; type: NamedResource }[];
  abilities: { ability: NamedResource; is_hidden: boolean }[];
  stats: { base_stat: number; stat: NamedResource }[];
  species: NamedResource;
}

interface Localized {
  language: NamedResource;
}

export interface Species {
  names: (Localized & { name: string })[];
  genera: (Localized & { genus: string })[];
  flavor_text_entries: (Localized & { flavor_text: string })[];
  evolution_chain: { url: string };
}

export interface ChainLink {
  species: NamedResource;
  evolution_details: {
    trigger: NamedResource;
    min_level: number | null;
    item: NamedResource | null;
    held_item: NamedResource | null;
    min_happiness: number | null;
    time_of_day: string;
    known_move: NamedResource | null;
  }[];
  evolves_to: ChainLink[];
}

// Each URL is fetched once while the extension runs; a failed request is forgotten so it can be tried again.
const responses = new Map<string, Promise<unknown>>();

export function getJSON<T>(url: string): Promise<T> {
  let response = responses.get(url);
  if (!response) {
    response = fetch(url).then((result) => {
      if (!result.ok) throw new Error(result.status === 404 ? "There's no such Pokémon." : `PokéAPI answered ${result.status}.`);
      return result.json();
    });
    response.catch(() => responses.delete(url));
    responses.set(url, response);
  }
  return response as Promise<T>;
}

/** The number at the end of a resource's URL, such as 25 for `…/pokemon/25/`. */
export function idFromURL(url: string) {
  return Number(url.split("/").filter(Boolean).pop());
}

/** Every Pokémon's number and name, kept between launches since it rarely changes. */
export async function loadIndex(): Promise<Entry[]> {
  const cached = await LocalStorage.getItem("index");
  if (cached) return JSON.parse(cached);
  const list = await getJSON<{ results: NamedResource[] }>(`${API}/pokemon?limit=${LAST_NUMBER}`);
  const entries = list.results.map((result) => ({ id: idFromURL(result.url), name: result.name }));
  await LocalStorage.setItem("index", JSON.stringify(entries));
  return entries;
}

export function loadPokemon(nameOrNumber: string | number) {
  return getJSON<Pokemon>(`${API}/pokemon/${nameOrNumber}`);
}

export function loadSpecies(pokemon: Pokemon) {
  return getJSON<Species>(pokemon.species.url);
}

export async function loadEvolutions(pokemon: Pokemon) {
  const species = await loadSpecies(pokemon);
  return (await getJSON<{ chain: ChainLink }>(species.evolution_chain.url)).chain;
}

/** The Pokémon of a type, leaving out alternate forms. */
export async function loadType(type: string): Promise<Entry[]> {
  const result = await getJSON<{ pokemon: { pokemon: NamedResource }[] }>(`${API}/type/${type}`);
  return result.pokemon
    .map(({ pokemon }) => ({ id: idFromURL(pokemon.url), name: pokemon.name }))
    .filter((entry) => entry.id <= LAST_NUMBER);
}

export function speciesName(nameOrNumber: string | number) {
  return getJSON<Species>(`${API}/pokemon-species/${nameOrNumber}`).then(
    (species) => english(species.names)?.name ?? String(nameOrNumber),
  );
}

export function english<T extends Localized>(entries: T[]): T | undefined {
  return entries.find((entry) => entry.language.name === "en");
}

export function sprite(id: number, shiny: boolean) {
  return `${SPRITES}/${shiny ? "shiny/" : ""}${id}.png`;
}

export function artwork(id: number, shiny: boolean) {
  return `${SPRITES}/other/official-artwork/${shiny ? "shiny/" : ""}${id}.png`;
}

/** `mr-mime` as `Mr Mime`. */
export function displayName(name: string) {
  return name
    .split("-")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

export function pokedexNumber(id: number) {
  return `#${String(id).padStart(3, "0")}`;
}

export function bulbapedia(name: string) {
  return `https://bulbapedia.bulbagarden.net/wiki/${encodeURIComponent(displayName(name).replace(/ /g, "_"))}_(Pokémon)`;
}

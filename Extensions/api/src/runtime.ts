// The runtime Whippet loads into each extension's JavaScript context before the extension's own script. It defines the
// web APIs extensions expect, then `__whippet`, which Whippet calls to load the extension, launch its commands and pass
// on what the user does.
import "./globals";
import * as React from "react";
import * as JSXRuntime from "react/jsx-runtime";
import * as API from "./api";
import * as PublicAPI from "./index";
import { RouterRoot, type RouterController } from "./router";
import { post } from "./native";
import { dispatch, mount, unmount } from "./renderer";

/** What `require` returns in an extension's bundle, which leaves these packages out so every extension shares them. */
const modules: Record<string, unknown> = {
  react: React,
  "react/jsx-runtime": JSXRuntime,
  "react/jsx-dev-runtime": JSXRuntime,
  "@whippet/api": PublicAPI,
};

let commands: Record<string, unknown> = {};
const controllers = new Map<string, RouterController>();

function reportError(session: string | undefined, error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  post({ type: "error", session, message, stack: error instanceof Error ? error.stack : undefined });
}

const whippet = {
  /**
   * Runs the extension's bundle, a CommonJS module, and keeps its exports: one function per command, named as in the
   * manifest, or the same on its default export.
   */
  load(factory: (module: { exports: unknown }, exports: unknown, require: (name: string) => unknown) => void) {
    const module = { exports: {} as Record<string, unknown> };
    factory(module, module.exports, (name: string) => {
      if (name in modules) return modules[name];
      throw new Error(`Cannot find module "${name}". Extensions can only import react and @whippet/api.`);
    });
    const exports = module.exports as Record<string, unknown>;
    const fallback = exports.default;
    commands = { ...(typeof fallback === "object" && fallback ? (fallback as Record<string, unknown>) : {}), ...exports };
  },

  configure(json: string) {
    const { environment, preferences } = JSON.parse(json);
    Object.assign(API.environment, environment);
    API.setPreferences(preferences ?? {});
  },

  /** Shows a view command, or runs one without a view and reports when it finishes. */
  launch(session: string, command: string, mode: string, argumentsJSON: string, fallbackText: string | null) {
    API.environment.commandName = command;
    const props: API.LaunchProps = { arguments: JSON.parse(argumentsJSON) };
    if (fallbackText !== null) props.fallbackText = fallbackText;
    const entry = commands[command];
    if (typeof entry !== "function") {
      reportError(session, new Error(`The extension doesn't export a function named "${command}".`));
      return;
    }
    if (mode === "no-view") {
      Promise.resolve()
        .then(() => (entry as (props: API.LaunchProps) => unknown)(props))
        .then(() => post({ type: "done", session }))
        .catch((error) => reportError(session, error));
      return;
    }
    const element = React.createElement(entry as React.FunctionComponent<API.LaunchProps>, props);
    mount(
      session,
      React.createElement(RouterRoot, {
        command: element,
        controller: (controller: RouterController) => controllers.set(session, controller),
      }),
    );
  },

  dispatch(session: string, handler: string, argsJSON: string) {
    dispatch(session, handler, JSON.parse(argsJSON));
  },

  /** Escape: goes back in the command's history, returning false on its first entry so Whippet can leave it. */
  pop(session: string): boolean {
    return controllers.get(session)?.back() ?? false;
  },

  popToRoot(session: string) {
    controllers.get(session)?.popToRoot();
  },

  close(session: string) {
    controllers.delete(session);
    unmount(session);
  },
};

(globalThis as Record<string, unknown>).__whippet = whippet;

import { Match, Show, Switch } from "solid-js";

import { Trans } from "@lingui/solid/macro";
import { css } from "styled-system/css";

import { useClientLifecycle } from "@revolt/client";
import { TransitionType } from "@revolt/client/Controller";
import { Navigate } from "@revolt/routing";
import { Button, Column } from "@revolt/ui";

import { useState } from "@revolt/state";
import Wordmark from "../../../../public/assets/web/wordmark.svg?component-solid";

/**
 * Flow for logging into an account
 */
export default function FlowHome() {
  const state = useState();
  const { lifecycle, isLoggedIn, isError } = useClientLifecycle();

  return (
    <Switch
      fallback={
        <>
          <Show when={isLoggedIn()}>
            <Navigate href={state.layout.popNextPath() ?? "/app"} />
          </Show>

          <Column gap="xl">
            <Wordmark
              class={css({
                width: "60%",
                margin: "auto",
                fill: "var(--md-sys-color-on-surface)",
              })}
            />

            <Column>
              <b
                style={{
                  "font-weight": 800,
                  "font-size": "1.4em",
                  display: "flex",
                  "flex-direction": "column",
                  "align-items": "center",
                  "text-align": "center",
                }}
              >
                <span>
                  <Trans>Find Your People. Join the Conversation.</Trans>
                </span>
              </b>
              <span style={{ "text-align": "center", opacity: "0.5" }}>
                <Trans>
                  One place to connect, discover communities, and be part of
                  conversations that matter to you.
                </Trans>
              </span>
            </Column>

            <Column>
              <a href="/login/auth">
                <Column>
                  <Button>
                    <Trans>Log In</Trans>
                  </Button>
                </Column>
              </a>
              <a href="/login/create">
                <Column>
                  <Button variant="tonal">
                    <Trans>Create Your Account</Trans>
                  </Button>
                </Column>
              </a>
            </Column>
          </Column>
        </>
      }
    >
      <Match when={isError()}>
        <Switch fallback={"an unknown error occurred"}>
          <Match when={lifecycle.permanentError === "InvalidSession"}>
            <h1>
              <Trans>You were logged out!</Trans>
            </h1>
          </Match>
        </Switch>

        <Button
          variant="filled"
          onPress={() =>
            lifecycle.transition({
              type: TransitionType.Dismiss,
            })
          }
        >
          <Trans>OK</Trans>
        </Button>
      </Match>
    </Switch>
  );
}

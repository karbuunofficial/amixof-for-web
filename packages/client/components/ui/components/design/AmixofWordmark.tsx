import type { JSX } from "solid-js";

/**
 * AMIXOF wordmark as inline SVG. Do not import wordmark.svg via ?component-solid:
 * vite-plugin-solid-svg drops <text> children, which renders an empty logo.
 */
export function AmixofWordmark(props: JSX.IntrinsicElements["svg"]) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 212 64"
      fill="currentColor"
      role="img"
      aria-label="AMIXOF"
      {...props}
    >
      <title>AMIXOF</title>
      <text
        x="106"
        y="50"
        text-anchor="middle"
        font-family="Arial, Helvetica, sans-serif"
        font-size="52"
        font-weight="700"
        letter-spacing="1"
      >
        AMIXOF
      </text>
    </svg>
  );
}

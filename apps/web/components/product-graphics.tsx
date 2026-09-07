export function WaterfallGraphic() {
  return (
    <svg
      aria-label="Senior and junior settlement waterfall"
      className="featureGraphic"
      role="img"
      viewBox="0 0 480 260"
    >
      <title>Settlement waterfall</title>
      <path d="M44 44h392v172H44z" fill="none" stroke="currentColor" />
      <path d="M44 123h392" stroke="currentColor" />
      <path
        d="M104 44v172M376 44v172"
        stroke="currentColor"
        strokeDasharray="4 5"
      />
      <path
        d="m218 92 22 22 22-22M240 114v52"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
      />
      <text x="68" y="91">
        SENIOR / FIRST
      </text>
      <text x="68" y="172">
        JUNIOR / RESIDUAL
      </text>
      <text x="350" y="91">
        01
      </text>
      <text x="350" y="172">
        02
      </text>
    </svg>
  );
}

export function RangeGraphic() {
  return (
    <svg
      aria-label="Static liquidity range and protection threshold"
      className="featureGraphic"
      role="img"
      viewBox="0 0 480 260"
    >
      <title>Static liquidity range</title>
      <path
        d="M48 206h384M71 224V45M71 206l82-34 72-90 74 52 106-94"
        fill="none"
        stroke="currentColor"
      />
      <path
        d="M111 206V73M370 206V73"
        stroke="currentColor"
        strokeDasharray="4 5"
      />
      <path d="M112 72h258v134H112z" fill="currentColor" opacity=".08" />
      <circle cx="299" cy="134" fill="currentColor" r="6" />
      <text x="91" y="238">
        LOWER
      </text>
      <text x="349" y="238">
        UPPER
      </text>
      <text x="311" y="126">
        SPOT
      </text>
    </svg>
  );
}

type BrandMarkProps = {
  className?: string;
};

export function BrandMark({ className }: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      viewBox="0 0 42 42"
    >
      <path d="M3 4h36L21 38 3 4Z" fill="currentColor" />
      <path d="m11 11 10 19 10-19H11Z" fill="white" />
      <path d="m16 15 5 10 5-10H16Z" fill="currentColor" />
    </svg>
  );
}

export function ArrowMark({ className }: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      viewBox="0 0 18 18"
    >
      <path d="M3 9h11M10 4l5 5-5 5" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}

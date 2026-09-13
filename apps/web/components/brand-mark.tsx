type BrandMarkProps = {
  className?: string;
};

export function BrandMark({ className }: BrandMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      viewBox="0 0 64 64"
    >
      <rect width="64" height="64" rx="16" fill="var(--red)" />
      <path d="M12 14h40L32 53 12 14Z" fill="#fff" />
      <path d="m22 23 10 20 10-20H22Z" fill="var(--red)" />
      <path d="m28 27 4 9 4-9h-8Z" fill="#fff" />
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

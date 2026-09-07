"use client";

import { motion, useReducedMotion, useScroll, useSpring } from "motion/react";
import type { ReactNode } from "react";

export function ScrollProgress() {
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, {
    damping: 30,
    stiffness: 200,
  });

  return (
    <motion.div
      aria-hidden="true"
      className="scrollProgress"
      style={{ scaleX }}
    />
  );
}

export function Reveal({
  children,
  className,
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  const reduceMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={reduceMotion ? false : { opacity: 0, y: 28 }}
      transition={{ delay, duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
      viewport={{ amount: 0.2, once: true }}
      whileInView={{ opacity: 1, y: 0 }}
    >
      {children}
    </motion.div>
  );
}

export function HeroArtwork({ children }: { children: ReactNode }) {
  const reduceMotion = useReducedMotion();

  if (reduceMotion) {
    return <div className="heroArtwork">{children}</div>;
  }

  return (
    <motion.div
      animate={{ y: [0, -10, 0], rotate: [0, -0.5, 0] }}
      className="heroArtwork"
      initial={{ opacity: 0, scale: 0.92 }}
      transition={{
        opacity: { duration: 0.9 },
        rotate: {
          duration: 7,
          ease: "easeInOut",
          repeat: Number.POSITIVE_INFINITY,
        },
        scale: { duration: 0.9, ease: [0.22, 1, 0.36, 1] },
        y: {
          duration: 7,
          ease: "easeInOut",
          repeat: Number.POSITIVE_INFINITY,
        },
      }}
    >
      {children}
    </motion.div>
  );
}

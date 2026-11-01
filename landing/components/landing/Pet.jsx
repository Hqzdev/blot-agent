"use client";

import { useRef } from "react";
import { useAnimationFrame, useInView, useReducedMotion } from "motion/react";
import frames from "@/lib/landing/pet-motion.json";
import { roles } from "@/lib/landing/content";

export function Pet({ size = 56, color = "currentColor", animated = true, className = "", outline = false, timeOffset = 0 }) {
  const svg = useRef(null);
  const paths = useRef([]);
  const visible = useInView(svg, { margin: "100px" });
  const reduced = useReducedMotion();
  const previous = useRef(-1);

  useAnimationFrame((time) => {
    if (!animated || reduced || !visible) return;
    const position = (time + timeOffset) % (frames.at(-1).time + 200);
    const index = frames.findIndex((frame) => frame.time >= position);
    const next = index < 0 ? frames.length - 1 : index;
    if (previous.current === next) return;
    previous.current = next;
    frames[next].paths.forEach((d, i) => paths.current[i]?.setAttribute("d", d));
  });

  return (
    <svg ref={svg} className={`blot-pet ${className}`} width={size} height={size} viewBox="16 16 60 60" aria-hidden="true" style={{ color }}>
      {frames[0].paths.map((d, i) => <path key={i} ref={(node) => { paths.current[i] = node; }} d={d} fill={outline ? "none" : i === 0 ? "currentColor" : "var(--blot-paper, #fff)"} stroke={outline ? "currentColor" : undefined} strokeWidth={outline ? 0.12 : undefined} fillRule="evenodd" />)}
    </svg>
  );
}

export function Avatar({ name, size = 32, className = "" }) {
  const roleIndex = roles.findIndex(role => name === `role-${role.id}`);
  if (roleIndex !== -1) return <Pet size={size} color={roles[roleIndex].color} className={`blot-avatar ${className}`} timeOffset={roleIndex * 713} />;
  return <img className={`blot-avatar ${className}`} src={`/blot/pets/${name}.svg`} width={size} height={size} alt="" draggable="false" />;
}

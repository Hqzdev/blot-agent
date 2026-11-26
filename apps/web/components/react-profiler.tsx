'use client';

import { Profiler, ProfilerOnRenderCallback } from 'react';
import { useEffect } from 'react';

interface ProfilerWrapperProps {
  id: string;
  children: React.ReactNode;
  onRender?: ProfilerOnRenderCallback;
}

export function ProfilerWrapper({
  id,
  children,
  onRender,
}: ProfilerWrapperProps) {
  const defaultOnRender: ProfilerOnRenderCallback = (
    id,
    phase,
    actualDuration,
    baseDuration,
    startTime,
    commitTime,
  ) => {
    if (process.env.NODE_ENV === 'development') {
      console.log(`[React Profiler] ${id}:`, {
        phase,
        actualDuration: `${actualDuration.toFixed(2)}ms`,
        baseDuration: `${baseDuration.toFixed(2)}ms`,
        startTime: `${startTime.toFixed(2)}ms`,
        commitTime: `${commitTime.toFixed(2)}ms`,
      });
    }

    if (process.env.NODE_ENV === 'production' && actualDuration > 16) {
      if (typeof window !== 'undefined' && (window as any).ym) {
        (window as any).ym(103415484, 'reachGoal', 'slow_render', {
          component: id,
          duration: actualDuration,
          phase,
        });
      }
    }
  };

  return (
    <Profiler id={id} onRender={onRender || defaultOnRender}>
      {children}
    </Profiler>
  );
}

export function useProfiler(id: string) {
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      const startTime = performance.now();
      return () => {
        const endTime = performance.now();
        const duration = endTime - startTime;
        if (duration > 16) {
          console.warn(
            `[Performance] ${id} took ${duration.toFixed(2)}ms to render`,
          );
        }
      };
    }
  }, [id]);
}

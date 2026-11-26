'use client';

import { useEffect } from 'react';
import type { Metric } from 'web-vitals';

export function WebVitals() {
  useEffect(() => {
    if (typeof window === 'undefined') return;

    const reportWebVitals = (metric: Metric) => {
      if (process.env.NODE_ENV === 'production') {
        if (typeof window !== 'undefined' && (window as any).ym) {
          (window as any).ym(103415484, 'reachGoal', 'web_vital', {
            name: metric.name,
            value: metric.value,
            id: metric.id,
            delta: metric.delta,
          });
        }
      } else {
        console.log('[Web Vitals]', metric);
      }
    };

    import('web-vitals')
      .then(({ onCLS, onFCP, onLCP, onTTFB, onINP }) => {
        onCLS(reportWebVitals);
        onFCP(reportWebVitals);
        onLCP(reportWebVitals);
        onTTFB(reportWebVitals);
        onINP(reportWebVitals);
      })
      .catch((error) => {
        if (process.env.NODE_ENV === 'development') {
          console.warn('[Web Vitals] Failed to load:', error);
        }
      });
  }, []);

  return null;
}

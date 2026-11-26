import { SWRConfiguration } from 'swr';

export const swrConfig: SWRConfiguration = {
  dedupingInterval: 2000,

  revalidateOnFocus: false,
  revalidateOnReconnect: true,

  revalidateIfStale: true,

  refreshInterval: 0,

  shouldRetryOnError: true,
  errorRetryCount: 3,
  errorRetryInterval: 5000,
};

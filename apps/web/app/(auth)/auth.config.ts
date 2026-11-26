import type { NextAuthConfig } from 'next-auth';

export const authConfig = {
  basePath: '/app/api/auth',
  callbacks: {
    authorized({ auth, request: { nextUrl } }) {
      const isLoggedIn = Boolean(auth?.user);
      const pathname = nextUrl.pathname;
      const isPublicPath = [
        '/',
        '/login',
        '/register',
        '/policy',
        '/privacy',
        '/auth/error',
      ].some((path) => pathname === path || pathname.startsWith(`${path}/`));

      if (pathname.startsWith('/api/auth')) {
        return true;
      }
      return isPublicPath || isLoggedIn;
    },
  },
  pages: {
    error: '/app/auth/error',
    newUser: '/app/chat',
    signIn: '/app/login',
  },
  providers: [],
} satisfies NextAuthConfig;

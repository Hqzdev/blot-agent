import { BlotAccountClient } from '@/lib/auth/blot-account-client';
import type { Plan } from '@teya/contracts';
import NextAuth, { type DefaultSession } from 'next-auth';
import Credentials from 'next-auth/providers/credentials';
import { cache } from 'react';
import { authConfig } from './auth.config';

declare module 'next-auth' {
  interface User {
    nickname: string;
    subscription?: Plan;
    blotAccessToken?: string;
    blotExpiresAt?: string;
  }
  interface Session {
    user: {
      id?: string;
      nickname: string;
      subscription?: Plan;
    } & DefaultSession['user'];
  }
}
declare module 'next-auth/jwt' {
  interface JWT {
    blotAccessToken?: string;
    blotExpiresAt?: string;
    blotSession?: boolean;
    nickname?: string;
  }
}

const authentication = NextAuth({
  ...authConfig,
  session: { strategy: 'jwt', maxAge: 600 },
  callbacks: {
    ...authConfig.callbacks,
    async jwt({ token, user }) {
      if (user) {
        token.sub = user.id;
        token.blotAccessToken = user.blotAccessToken;
        token.blotExpiresAt = user.blotExpiresAt;
        token.blotSession = true;
      }
      if (
        !token.sub ||
        !token.blotSession ||
        !token.blotAccessToken ||
        !token.blotExpiresAt ||
        Date.parse(token.blotExpiresAt) <= Date.now()
      )
        return null;
      try {
        const account = await new BlotAccountClient().profile(
          token.blotAccessToken,
        );
        if (account.id !== token.sub) return null;
        token.name = account.name;
        token.nickname = account.name;
        token.email = account.email;
        token.picture = account.avatarURL;
        return token;
      } catch {
        return null;
      }
    },
    async session({ session, token }) {
      session.user.id = token.sub || '';
      session.user.nickname = token.nickname || token.name || '';
      const expires =
        token.blotExpiresAt &&
        Date.parse(token.blotExpiresAt) < Date.parse(session.expires)
          ? token.blotExpiresAt
          : session.expires;
      return { ...session, expires };
    },
  },
  providers: [
    Credentials({
      id: 'blot',
      name: 'Ori',
      credentials: { code: {}, codeVerifier: {} },
      async authorize(credentials) {
        if (
          typeof credentials.code !== 'string' ||
          !/^[A-Za-z0-9_-]{43}$/.test(credentials.code) ||
          typeof credentials.codeVerifier !== 'string' ||
          !/^[A-Za-z0-9._~-]{43,128}$/.test(credentials.codeVerifier)
        )
          return null;
        const { tokens, account } = await new BlotAccountClient().exchange(
          credentials.code,
          credentials.codeVerifier,
        );
        return {
          id: account.id,
          name: account.name,
          nickname: account.name,
          email: account.email,
          image: account.avatarURL,
          blotAccessToken: tokens.accessToken,
          blotExpiresAt: tokens.expiresAt,
        };
      },
    }),
  ],
  events: {
    async signOut(message) {
      if ('token' in message && message.token?.blotAccessToken) {
        try {
          await new BlotAccountClient().logout(message.token.blotAccessToken);
        } catch {
          console.warn('Ori remote session revocation could not be confirmed');
        }
      }
    },
  },
  trustHost: true,
});

export const auth = cache(async () => authentication.auth());
export const { handlers, signIn, signOut } = authentication;

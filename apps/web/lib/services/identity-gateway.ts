import 'server-only';
import { auth } from '@/app/(auth)/auth';
import type { Customization, Plan } from '@teya/contracts';
import { getBillingGateway } from './billing-gateway';
import { BlotProfileRepository } from './blot-profile-repository';

export interface AppUser {
  id: string;
  email: string;
  nickname: string;
  password: null;
  customization: Customization | null;
  subscription: Plan;
}

class BlotIdentityGateway {
  private readonly profiles = new BlotProfileRepository();

  private async owner(ownerID: string) {
    const session = await auth();
    if (session?.user?.id !== ownerID || !session.user.email)
      throw new Error('Blot account required');
    return session.user;
  }

  async getUser(ownerID: string): Promise<AppUser> {
    const user = await this.owner(ownerID);
    const profile = await this.profiles.get(ownerID);
    return {
      id: ownerID,
      email: user.email || '',
      nickname: profile?.nickname || user.nickname,
      password: null,
      customization: (profile?.customization as Customization | null) ?? null,
      subscription: await getBillingGateway().getSubscription(ownerID),
    };
  }

  async updateCustomization(ownerID: string, customization: Customization) {
    await this.owner(ownerID);
    await this.profiles.save(ownerID, { customization });
  }

  async updateNickname(ownerID: string, nickname: string) {
    await this.owner(ownerID);
    await this.profiles.save(ownerID, { nickname });
  }
}

const identity = new BlotIdentityGateway();
export function getIdentityGateway() {
  return identity;
}

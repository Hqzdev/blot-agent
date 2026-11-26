import 'server-only';

import type {
  LoadedSkill,
  SkillDetail,
  SkillInput,
  SkillSummary,
} from '@teya/contracts';
import { InternalApiClient } from '@teya/platform';
import {
  PostgresSkillRepository,
  SkillService,
} from '@teya/service-ai-gateway';

interface RpcResponse<T> {
  result: T;
}

export interface SkillGateway {
  createSkill(userId: string, input: SkillInput): Promise<SkillDetail>;
  deleteSkill(userId: string, id: string): Promise<void>;
  deleteUserData(userId: string): Promise<void>;
  getInstalledSkillSummaries(userId: string): Promise<SkillSummary[]>;
  getSkill(userId: string, id: string): Promise<SkillDetail>;
  installSkill(userId: string, id: string): Promise<SkillSummary>;
  listSkills(userId: string, query?: string): Promise<SkillSummary[]>;
  loadInstalledSkill(userId: string, id: string): Promise<LoadedSkill>;
  uninstallSkill(userId: string, id: string): Promise<SkillSummary>;
  updateSkill(
    userId: string,
    id: string,
    input: SkillInput,
  ): Promise<SkillDetail>;
}

class LocalSkillGateway implements SkillGateway {
  private readonly service = new SkillService(new PostgresSkillRepository());

  createSkill(userId: string, input: SkillInput) {
    return this.service.createSkill(userId, input);
  }

  deleteSkill(userId: string, id: string) {
    return this.service.deleteSkill(userId, id);
  }

  deleteUserData(userId: string) {
    return this.service.deleteUserData(userId);
  }

  getInstalledSkillSummaries(userId: string) {
    return this.service.getInstalledSkillSummaries(userId);
  }

  getSkill(userId: string, id: string) {
    return this.service.getSkill(userId, id);
  }

  installSkill(userId: string, id: string) {
    return this.service.installSkill(userId, id);
  }

  listSkills(userId: string, query?: string) {
    return this.service.listSkills(userId, query);
  }

  loadInstalledSkill(userId: string, id: string) {
    return this.service.loadInstalledSkill(userId, id);
  }

  uninstallSkill(userId: string, id: string) {
    return this.service.uninstallSkill(userId, id);
  }

  updateSkill(userId: string, id: string, input: SkillInput) {
    return this.service.updateSkill(userId, id, input);
  }
}

class HttpSkillGateway implements SkillGateway {
  private readonly client: InternalApiClient;

  constructor(baseUrl: string, secret: string) {
    this.client = new InternalApiClient(baseUrl, secret);
  }

  async createSkill(userId: string, input: SkillInput): Promise<SkillDetail> {
    return this.reviveDetail(
      await this.call(userId, {
        operation: 'createSkill',
        payload: input,
      }),
    );
  }

  async deleteSkill(userId: string, id: string): Promise<void> {
    await this.call(userId, {
      operation: 'deleteSkill',
      payload: { id },
    });
  }

  async deleteUserData(userId: string): Promise<void> {
    await this.call('system:web', {
      operation: 'deleteSkillUserData',
      payload: { userId },
    });
  }

  async getInstalledSkillSummaries(userId: string): Promise<SkillSummary[]> {
    const rows = await this.call<SkillSummary[]>(userId, {
      operation: 'getInstalledSkillSummaries',
      payload: {},
    });
    return rows.map((row) => this.reviveSummary(row));
  }

  async getSkill(userId: string, id: string): Promise<SkillDetail> {
    return this.reviveDetail(
      await this.call(userId, {
        operation: 'getSkill',
        payload: { id },
      }),
    );
  }

  async installSkill(userId: string, id: string): Promise<SkillSummary> {
    return this.reviveSummary(
      await this.call(userId, {
        operation: 'installSkill',
        payload: { id },
      }),
    );
  }

  async listSkills(userId: string, query?: string): Promise<SkillSummary[]> {
    const rows = await this.call<SkillSummary[]>(userId, {
      operation: 'listSkills',
      payload: { query },
    });
    return rows.map((row) => this.reviveSummary(row));
  }

  loadInstalledSkill(userId: string, id: string): Promise<LoadedSkill> {
    return this.call(userId, {
      operation: 'loadInstalledSkill',
      payload: { id },
    });
  }

  async uninstallSkill(userId: string, id: string): Promise<SkillSummary> {
    return this.reviveSummary(
      await this.call(userId, {
        operation: 'uninstallSkill',
        payload: { id },
      }),
    );
  }

  async updateSkill(
    userId: string,
    id: string,
    input: SkillInput,
  ): Promise<SkillDetail> {
    return this.reviveDetail(
      await this.call(userId, {
        operation: 'updateSkill',
        payload: { id, ...input },
      }),
    );
  }

  private async call<T>(actorId: string, body: unknown): Promise<T> {
    const response = await this.client.request<RpcResponse<T>>({
      actorId,
      body,
      path: '/api/skills',
    });
    return response.result;
  }

  private reviveSummary(skill: SkillSummary): SkillSummary {
    return {
      ...skill,
      createdAt: new Date(skill.createdAt),
      updatedAt: new Date(skill.updatedAt),
    };
  }

  private reviveDetail(skill: SkillDetail): SkillDetail {
    return {
      ...skill,
      createdAt: new Date(skill.createdAt),
      updatedAt: new Date(skill.updatedAt),
    };
  }
}

let skillGateway: SkillGateway | undefined;

export function getSkillGateway(): SkillGateway {
  if (skillGateway) {
    return skillGateway;
  }
  const serviceUrl = process.env.AI_GATEWAY_URL;
  const secret = process.env.INTERNAL_SERVICE_SECRET;
  skillGateway =
    serviceUrl && secret
      ? new HttpSkillGateway(serviceUrl, secret)
      : new LocalSkillGateway();
  return skillGateway;
}

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TextStore } from './PlanRepository';

export class PreferencesStore implements TextStore {
  private preferences: preferences.Preferences;
  private key: string = 'plans.v1';

  private constructor(instance: preferences.Preferences) {
    this.preferences = instance;
  }

  static async open(context: common.UIAbilityContext): Promise<PreferencesStore> {
    const instance = await preferences.getPreferences(context, { name: 'corner_plan' });
    return new PreferencesStore(instance);
  }

  async read(): Promise<string> {
    const value = await this.preferences.get(this.key, '');
    if (typeof value !== 'string') {
      throw new Error('方案库的存储值无效');
    }
    return value;
  }

  async write(text: string): Promise<void> {
    const previous = await this.read();
    try {
      await this.preferences.put(this.key, text);
      await this.preferences.flush();
    } catch (error) {
      await this.preferences.put(this.key, previous);
      await this.preferences.flush();
      throw new Error('本地保存失败，可重试');
    }
  }
}

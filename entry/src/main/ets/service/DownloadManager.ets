import { preferences } from '@kit.ArkData';
import { request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

const PREFS_NAME: string = 'download_tasks';
const KEY_TASKS: string = 'task_list';

/**
 * 下载任务
 */
export interface DownloadTask {
  id: string;
  title: string;
  url: string;
  progress: number;       // 0-100
  status: DownloadStatus;  // current status
  savedPath: string;       // final saved file path
  totalBytes: number;
  downloadedBytes: number;
  createdAt: number;
  completedAt: number;
  errorMessage: string;
}

export enum DownloadStatus {
  QUEUED = 'queued',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

// Internal tracking
interface ActiveDownload {
  taskId: string;
  downloadTask: request.DownloadTask | null;
}

/**
 * 视频下载管理器
 */
export class DownloadManager {
  private static instance: DownloadManager | null = null;
  private prefs: preferences.Preferences | null = null;
  private tasks: DownloadTask[] = [];
  private activeDownloads: Map<string, ActiveDownload> = new Map();
  private maxConcurrent: number = 2;
  private onChangeCallback: (() => void) | null = null;
  private appContext: common.Context | null = null;

  static getInstance(): DownloadManager {
    if (DownloadManager.instance === null) {
      DownloadManager.instance = new DownloadManager();
    }
    return DownloadManager.instance;
  }

  setContext(ctx: common.Context): void {
    this.appContext = ctx;
  }

  private getCtx(): common.Context {
    if (this.appContext === null) {
      throw new Error('DownloadManager: context not set');
    }
    return this.appContext;
  }

  /**
   * 设置状态变更回调（用于 UI 刷新）
   */
  setOnChange(callback: () => void): void {
    this.onChangeCallback = callback;
  }

  private notifyChange(): void {
    if (this.onChangeCallback) {
      this.onChangeCallback();
    }
  }

  private async getPrefs(): Promise<preferences.Preferences> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(this.getCtx(), PREFS_NAME);
    }
    return this.prefs;
  }

  /**
   * 加载已保存的下载任务
   */
  async loadTasks(): Promise<DownloadTask[]> {
    const prefs = await this.getPrefs();
    const data = await prefs.get(KEY_TASKS, '[]') as string;
    this.tasks = JSON.parse(data) as DownloadTask[];

    // Reset any stale 'downloading' status
    for (const task of this.tasks) {
      if (task.status === DownloadStatus.DOWNLOADING) {
        task.status = DownloadStatus.QUEUED;
      }
    }
    return this.tasks;
  }

  /**
   * 获取所有下载任务
   */
  getTasks(): DownloadTask[] {
    return this.tasks;
  }

  /**
   * 添加下载任务
   */
  async addTask(title: string, url: string): Promise<DownloadTask> {
    const task: DownloadTask = {
      id: `dl_${Date.now()}`,
      title: title,
      url: url,
      progress: 0,
      status: DownloadStatus.QUEUED,
      savedPath: '',
      totalBytes: 0,
      downloadedBytes: 0,
      createdAt: Date.now(),
      completedAt: 0,
      errorMessage: ''
    };
    this.tasks.unshift(task);
    await this.saveTasks();
    this.notifyChange();
    this.processQueue();
    return task;
  }

  /**
   * 开始/恢复下载
   */
  async startTask(taskId: string): Promise<void> {
    const task = this.tasks.find(t => t.id === taskId);
    if (!task || task.status === DownloadStatus.COMPLETED) return;

    task.status = DownloadStatus.QUEUED;
    task.errorMessage = '';
    await this.saveTasks();
    this.notifyChange();
    this.processQueue();
  }

  /**
   * 暂停下载
   */
  async pauseTask(taskId: string): Promise<void> {
    const active = this.activeDownloads.get(taskId);
    if (active && active.downloadTask) {
      try {
        active.downloadTask.delete();
      } catch (e) {
        console.warn('[DownloadManager] pause delete failed');
      }
      this.activeDownloads.delete(taskId);
    }

    const task = this.tasks.find(t => t.id === taskId);
    if (task && task.status === DownloadStatus.DOWNLOADING) {
      task.status = DownloadStatus.PAUSED;
      await this.saveTasks();
      this.notifyChange();
      this.processQueue();
    }
  }

  /**
   * 取消并删除下载任务
   */
  async removeTask(taskId: string): Promise<void> {
    await this.pauseTask(taskId);
    const task = this.tasks.find(t => t.id === taskId);
    if (task && task.savedPath.length > 0) {
      try {
        fileIo.unlinkSync(task.savedPath);
      } catch (e) {
        // File may not exist
      }
    }
    this.tasks = this.tasks.filter(t => t.id !== taskId);
    await this.saveTasks();
    this.notifyChange();
  }

  /**
   * 处理下载队列
   */
  private async processQueue(): Promise<void> {
    const downloading = this.tasks.filter(t => t.status === DownloadStatus.DOWNLOADING);
    if (downloading.length >= this.maxConcurrent) return;

    const queued = this.tasks.filter(t => t.status === DownloadStatus.QUEUED);
    const slots = this.maxConcurrent - downloading.length;

    for (let i = 0; i < Math.min(slots, queued.length); i++) {
      this.downloadFile(queued[i]);
    }
  }

  /**
   * 执行文件下载
   */
  private async downloadFile(task: DownloadTask): Promise<void> {
    task.status = DownloadStatus.DOWNLOADING;
    task.errorMessage = '';
    await this.saveTasks();
    this.notifyChange();

    // Build save path
    const ext = this.getExtension(task.url);
    const fileName = `${task.title.replace(/[\\/:*?"<>|]/g, '_')}${ext}`;
    const downloadDir = this.getDownloadDir();
    const savedPath = `${downloadDir}/${fileName}`;

    try {
      const downloadConfig: request.DownloadConfig = {
        url: task.url,
        filePath: savedPath,
        enableMetered: true,
        enableRoaming: false,
        networkType: 0 // 0 = any network
      } as request.DownloadConfig;

      const downloadTask = await request.downloadFile(this.getCtx(), downloadConfig);

      // Store active download
      this.activeDownloads.set(task.id, {
        taskId: task.id,
        downloadTask: downloadTask
      });

      // Progress listener
      downloadTask.on('progress', (receivedSize: number, totalSize: number) => {
        task.downloadedBytes = receivedSize;
        task.totalBytes = totalSize;
        task.progress = totalSize > 0 ? Math.round((receivedSize / totalSize) * 100) : 0;
        this.notifyChange();
      });

      // Complete listener
      downloadTask.on('complete', () => {
        task.status = DownloadStatus.COMPLETED;
        task.progress = 100;
        task.savedPath = savedPath;
        task.completedAt = Date.now();
        this.activeDownloads.delete(task.id);
        this.saveTasks();
        this.notifyChange();
        this.processQueue();
      });

      // Fail listener
      downloadTask.on('fail', (errCode: number) => {
        task.status = DownloadStatus.FAILED;
        task.errorMessage = `Download failed (code: ${errCode})`;
        this.activeDownloads.delete(task.id);
        this.saveTasks();
        this.notifyChange();
        this.processQueue();
      });

    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      task.status = DownloadStatus.FAILED;
      task.errorMessage = `Download error: ${errMsg}`;
      this.activeDownloads.delete(task.id);
      await this.saveTasks();
      this.notifyChange();
      this.processQueue();
    }
  }

  private getExtension(url: string): string {
    const lower = url.split('?')[0].toLowerCase();
    const dot = lower.lastIndexOf('.');
    if (dot >= 0) {
      const ext = lower.substring(dot);
      if (ext.length <= 6) return ext;
    }
    return '.mp4';
  }

  private getDownloadDir(): string {
    try {
      const dir = this.getCtx().filesDir + '/downloads';
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      return dir;
    } catch (e) {
      return this.getCtx().filesDir;
    }
  }

  private async saveTasks(): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(KEY_TASKS, JSON.stringify(this.tasks));
    await prefs.flush();
  }
}

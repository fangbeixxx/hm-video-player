import { Constants } from '../common/Constants';

export class FileUtils {
  static formatSize(bytes: number): string {
    if (bytes <= 0) return '0 B';

    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    let index = Math.floor(Math.log(bytes) / Math.log(k));
    if (index < 0) index = 0;
    if (index >= units.length) index = units.length - 1;

    const size = bytes / Math.pow(k, index);
    return `${size.toFixed(index > 0 ? 1 : 0)} ${units[index]}`;
  }

  static getExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    if (lastDot < 0) return '';
    return filePath.substring(lastDot).toLowerCase();
  }

  static getFileName(filePath: string): string {
    const slash = filePath.lastIndexOf('/');
    const backslash = filePath.lastIndexOf('\\');
    const lastSlash = Math.max(slash, backslash);
    const name = lastSlash < 0 ? filePath : filePath.substring(lastSlash + 1);
    const lastDot = name.lastIndexOf('.');
    return lastDot < 0 ? name : name.substring(0, lastDot);
  }

  static isSupportedVideo(filePath: string): boolean {
    const ext = FileUtils.getExtension(filePath);
    return Constants.SUPPORTED_FORMATS.indexOf(ext) >= 0;
  }

  static getProgress(currentTime: number, duration: number): number {
    if (duration <= 0) return 0;
    return Math.min(100, Math.max(0, (currentTime / duration) * 100));
  }
}

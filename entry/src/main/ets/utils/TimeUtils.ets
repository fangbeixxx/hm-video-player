export class TimeUtils {
  static formatTime(timeMs: number): string {
    let safeTime = timeMs;
    if (safeTime < 0) safeTime = 0;

    const totalSeconds = Math.floor(safeTime / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
      return `${TimeUtils.padZero(hours)}:${TimeUtils.padZero(minutes)}:${TimeUtils.padZero(seconds)}`;
    }
    return `${TimeUtils.padZero(minutes)}:${TimeUtils.padZero(seconds)}`;
  }

  static formatDuration(durationMs: number): string {
    const totalMinutes = Math.floor(durationMs / 60000);
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;

    if (hours > 0) {
      return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
    }
    return `${minutes}m`;
  }

  static formatRelativeTime(timestamp: number): string {
    const diff = Date.now() - timestamp;

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    if (diff < 172800000) return 'Yesterday';
    if (diff < 604800000) return `${Math.floor(diff / 86400000)}d ago`;

    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()}`;
  }

  private static padZero(num: number): string {
    return num < 10 ? `0${num}` : `${num}`;
  }
}

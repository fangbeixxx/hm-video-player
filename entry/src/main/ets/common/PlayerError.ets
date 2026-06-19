export enum PlayerErrorCode {
  UNKNOWN = 0,
  INIT_FAILED = 1001,
  ALREADY_RELEASED = 1002,
  FILE_NOT_FOUND = 2001,
  FILE_READ_ERROR = 2002,
  FILE_FORMAT_UNKNOWN = 2003,
  FILE_CORRUPTED = 2004,
  FILE_NO_STREAM = 2005,
  FILE_NO_VIDEO_STREAM = 2006,
  FILE_NO_AUDIO_STREAM = 2007,
  DECODER_NOT_FOUND = 3001,
  DECODER_OPEN_FAILED = 3002,
  DECODER_INIT_FAILED = 3003,
  DECODE_ERROR = 3004,
  UNSUPPORTED_CODEC = 3005,
  NETWORK_UNAVAILABLE = 4001,
  NETWORK_TIMEOUT = 4002,
  NETWORK_DNS_ERROR = 4003,
  NETWORK_CONNECTION_CLOSED = 4004,
  STREAM_NOT_FOUND = 4005,
  STREAM_FORBIDDEN = 4006,
  RENDERER_INIT_FAILED = 5001,
  RENDERER_SURFACE_ERROR = 5002,
  RENDERER_FORMAT_ERROR = 5003,
  AUDIO_INIT_FAILED = 6001,
  AUDIO_OUTPUT_ERROR = 6002,
  PERMISSION_DENIED = 7001
}

export interface PlayerError {
  code: PlayerErrorCode;
  title: string;
  message: string;
  detail: string;
  suggestion: string;
  recoverable: boolean;
  retryable: boolean;
}

class PlayerErrorTemplate {
  title: string;
  message: string;
  suggestion: string;
  recoverable: boolean;
  retryable: boolean;

  constructor(title: string, message: string, suggestion: string, recoverable: boolean, retryable: boolean) {
    this.title = title;
    this.message = message;
    this.suggestion = suggestion;
    this.recoverable = recoverable;
    this.retryable = retryable;
  }
}

function getTemplate(code: PlayerErrorCode): PlayerErrorTemplate {
  switch (code) {
    case PlayerErrorCode.INIT_FAILED:
      return new PlayerErrorTemplate('Initialization failed', 'The player could not be initialized.', 'Restart the app and try again.', false, true);
    case PlayerErrorCode.ALREADY_RELEASED:
      return new PlayerErrorTemplate('Player released', 'The player resources have already been released.', 'Open the video again.', false, true);
    case PlayerErrorCode.FILE_NOT_FOUND:
      return new PlayerErrorTemplate('File not found', 'The selected video file could not be found.', 'Check whether the file was moved or deleted.', false, false);
    case PlayerErrorCode.FILE_READ_ERROR:
      return new PlayerErrorTemplate('Read failed', 'The video file could not be read.', 'Check file permissions and storage status.', true, true);
    case PlayerErrorCode.FILE_FORMAT_UNKNOWN:
      return new PlayerErrorTemplate('Unsupported format', 'The video format could not be recognized.', 'Try another file or convert it to MP4.', false, false);
    case PlayerErrorCode.FILE_CORRUPTED:
      return new PlayerErrorTemplate('Damaged file', 'The video file appears to be incomplete or damaged.', 'Use a complete copy of this video.', false, false);
    case PlayerErrorCode.FILE_NO_STREAM:
      return new PlayerErrorTemplate('No media stream', 'No playable media stream was found in this file.', 'Choose a valid video file.', false, false);
    case PlayerErrorCode.FILE_NO_VIDEO_STREAM:
      return new PlayerErrorTemplate('No video stream', 'This file does not contain a video stream.', 'Open it with an audio player if it is an audio file.', false, false);
    case PlayerErrorCode.FILE_NO_AUDIO_STREAM:
      return new PlayerErrorTemplate('No audio stream', 'This video has no audio track.', 'Playback can continue without sound.', true, false);
    case PlayerErrorCode.DECODER_NOT_FOUND:
      return new PlayerErrorTemplate('Decoder missing', 'No decoder was found for this codec.', 'Try converting the video to H.264 or H.265.', false, false);
    case PlayerErrorCode.DECODER_OPEN_FAILED:
      return new PlayerErrorTemplate('Decoder failed', 'The video decoder could not be opened.', 'Try software decoding or another file.', true, true);
    case PlayerErrorCode.DECODER_INIT_FAILED:
      return new PlayerErrorTemplate('Decoder init failed', 'The decoder failed during initialization.', 'Try playing the video again.', true, true);
    case PlayerErrorCode.DECODE_ERROR:
      return new PlayerErrorTemplate('Decode error', 'An error occurred while decoding the video.', 'Skip this segment or try another file.', true, true);
    case PlayerErrorCode.UNSUPPORTED_CODEC:
      return new PlayerErrorTemplate('Unsupported codec', 'The codec used by this video is not supported.', 'Convert the video to H.264 MP4.', false, false);
    case PlayerErrorCode.NETWORK_UNAVAILABLE:
      return new PlayerErrorTemplate('Network unavailable', 'The network is not available.', 'Check Wi-Fi or mobile data and try again.', true, true);
    case PlayerErrorCode.NETWORK_TIMEOUT:
      return new PlayerErrorTemplate('Network timeout', 'The network request timed out.', 'Try again on a more stable network.', true, true);
    case PlayerErrorCode.NETWORK_DNS_ERROR:
      return new PlayerErrorTemplate('DNS failed', 'The server address could not be resolved.', 'Check the URL and network settings.', true, true);
    case PlayerErrorCode.NETWORK_CONNECTION_CLOSED:
      return new PlayerErrorTemplate('Connection closed', 'The connection was interrupted.', 'Try playing again.', true, true);
    case PlayerErrorCode.STREAM_NOT_FOUND:
      return new PlayerErrorTemplate('Stream not found', 'The remote video stream was not found.', 'Confirm the link is still valid.', false, false);
    case PlayerErrorCode.STREAM_FORBIDDEN:
      return new PlayerErrorTemplate('Access denied', 'The server refused access to this stream.', 'Check login or access permissions.', false, false);
    case PlayerErrorCode.RENDERER_INIT_FAILED:
      return new PlayerErrorTemplate('Renderer failed', 'The video renderer could not be initialized.', 'Leave playback and open the video again.', true, true);
    case PlayerErrorCode.RENDERER_SURFACE_ERROR:
      return new PlayerErrorTemplate('Surface error', 'The rendering surface is not available.', 'Re-enter the playback page.', true, true);
    case PlayerErrorCode.RENDERER_FORMAT_ERROR:
      return new PlayerErrorTemplate('Render format error', 'The video pixel format could not be converted.', 'Try software decoding.', true, true);
    case PlayerErrorCode.AUDIO_INIT_FAILED:
      return new PlayerErrorTemplate('Audio init failed', 'Audio output could not be initialized.', 'Check whether another app is using audio output.', true, true);
    case PlayerErrorCode.AUDIO_OUTPUT_ERROR:
      return new PlayerErrorTemplate('Audio output error', 'Audio playback failed.', 'The video may continue muted.', true, false);
    case PlayerErrorCode.PERMISSION_DENIED:
      return new PlayerErrorTemplate('Permission denied', 'The app does not have permission to read this file.', 'Grant media access permission in system settings.', false, false);
    default:
      return new PlayerErrorTemplate('Playback failed', 'An unknown playback error occurred.', 'Try again or play another video.', true, true);
  }
}

function contains(text: string, keyword: string): boolean {
  return text.indexOf(keyword) >= 0;
}

export function mapFFmpegError(ffmpegErrorCode: number, ffmpegErrorMsg: string): PlayerErrorCode {
  if (ffmpegErrorCode === -110) return PlayerErrorCode.NETWORK_TIMEOUT;
  if (ffmpegErrorCode === -111) return PlayerErrorCode.NETWORK_CONNECTION_CLOSED;
  if (ffmpegErrorCode === -113) return PlayerErrorCode.NETWORK_UNAVAILABLE;
  if (ffmpegErrorCode === -2) return PlayerErrorCode.FILE_NOT_FOUND;
  if (ffmpegErrorCode === -13) return PlayerErrorCode.PERMISSION_DENIED;
  if (ffmpegErrorCode === -5) return PlayerErrorCode.FILE_READ_ERROR;
  if (ffmpegErrorCode === -12) return PlayerErrorCode.DECODER_INIT_FAILED;

  const msg = ffmpegErrorMsg.toLowerCase();
  if (contains(msg, 'timeout')) return PlayerErrorCode.NETWORK_TIMEOUT;
  if (contains(msg, 'connection') && contains(msg, 'refused')) return PlayerErrorCode.NETWORK_CONNECTION_CLOSED;
  if (contains(msg, 'no such file')) return PlayerErrorCode.FILE_NOT_FOUND;
  if (contains(msg, 'permission')) return PlayerErrorCode.PERMISSION_DENIED;
  if (contains(msg, 'codec') && contains(msg, 'not found')) return PlayerErrorCode.DECODER_NOT_FOUND;
  if (contains(msg, 'invalid data') || contains(msg, 'corrupt')) return PlayerErrorCode.FILE_CORRUPTED;
  if (contains(msg, 'format') && contains(msg, 'not supported')) return PlayerErrorCode.FILE_FORMAT_UNKNOWN;
  if (contains(msg, 'no stream')) return PlayerErrorCode.FILE_NO_STREAM;
  if (contains(msg, 'http') && contains(msg, '404')) return PlayerErrorCode.STREAM_NOT_FOUND;
  if (contains(msg, 'http') && contains(msg, '403')) return PlayerErrorCode.STREAM_FORBIDDEN;

  return PlayerErrorCode.UNKNOWN;
}

export function createPlayerError(code: PlayerErrorCode, detail?: string): PlayerError {
  const template = getTemplate(code);
  const error: PlayerError = {
    code: code,
    title: template.title,
    message: template.message,
    detail: detail ? detail : `Error code: ${code}`,
    suggestion: template.suggestion,
    recoverable: template.recoverable,
    retryable: template.retryable
  };
  return error;
}

export function formatErrorMessage(error: PlayerError): string {
  if (error.suggestion.length > 0) {
    return `${error.message}\n${error.suggestion}`;
  }
  return error.message;
}

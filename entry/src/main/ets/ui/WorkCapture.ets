import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { SelectedWorkFile } from '../api/WorkUploadApi';

export interface WorkAudioCapture { recorder: media.AVRecorder; file: fs.File; path: string; }

// Both capture routes only stage a local file. The existing upload action remains
// the single place that can send an attachment to the server.
export async function takeWorkPhoto(context: common.UIAbilityContext): Promise<SelectedWorkFile> {
  const name: string = `work-photo-${Date.now()}.jpg`;
  const path: string = context.cacheDir + '/' + name;
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  fs.closeSync(file);
  try {
    const result: cameraPicker.PickerResult | undefined = await cameraPicker.pick(context,
      [cameraPicker.PickerMediaType.PHOTO], { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: fileUri.getUriFromPath(path) });
    if (!result) throw new Error('系统相机在当前设备上不可用');
    if (result.resultCode !== 0 || !result.resultUri) throw new Error('未取得照片');
    const stat: fs.Stat = fs.statSync(path);
    if (stat.size <= 0) throw new Error('照片文件为空');
    return { path: path, name: name, bytes: stat.size, mime: 'image/jpeg', modified: new Date(stat.mtime * 1000).toString() };
  } catch (error) {
    if (fs.accessSync(path)) fs.unlinkSync(path);
    throw error as Error;
  }
}

export async function startWorkRecording(context: common.UIAbilityContext): Promise<WorkAudioCapture> {
  const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
    ['ohos.permission.MICROPHONE' as Permissions]);
  if (permission.authResults[0] !== 0) throw new Error('未获得麦克风权限');
  const path: string = context.cacheDir + `/work-record-${Date.now()}.m4a`;
  const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  let recorder: media.AVRecorder | undefined = undefined;
  try {
    recorder = await media.createAVRecorder();
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: { audioBitrate: 64000, audioChannels: 1, audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: 44100, fileFormat: media.ContainerFormatType.CFT_MPEG_4A },
      url: `fd://${file.fd}`
    };
    await recorder.prepare(config);
    await recorder.start();
    return { recorder: recorder, file: file, path: path };
  } catch (error) {
    if (recorder) {
      try { await recorder.release(); } catch (_) {}
    }
    fs.closeSync(file);
    if (fs.accessSync(path)) fs.unlinkSync(path);
    throw error as Error;
  }
}

export async function finishWorkRecording(capture: WorkAudioCapture, keep: boolean): Promise<SelectedWorkFile | undefined> {
  let failure: Error | undefined = undefined;
  try {
    await capture.recorder.stop();
  } catch (error) {
    failure = error as Error;
  } finally {
    try { await capture.recorder.release(); }
    catch (error) { if (!failure) failure = error as Error; }
    fs.closeSync(capture.file);
  }
  if (!keep || failure) {
    if (fs.accessSync(capture.path)) fs.unlinkSync(capture.path);
    if (failure) throw failure;
    return undefined;
  }
  const stat: fs.Stat = fs.statSync(capture.path);
  if (stat.size <= 0) {
    fs.unlinkSync(capture.path);
    throw new Error('录音文件为空');
  }
  const name: string = capture.path.substring(capture.path.lastIndexOf('/') + 1);
  return { path: capture.path, name: name, bytes: stat.size,
    mime: 'audio/mp4', modified: new Date(stat.mtime * 1000).toString() };
}

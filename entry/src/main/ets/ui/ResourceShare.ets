import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { formatAttachmentSize } from '../common/FormatSize';

// Official Share Kit host API: SharedRecord.utd + uri, then ShareController.show.
// Only local file metadata crosses IPC; the document is never loaded into a JS buffer.
export async function shareResource(context: common.UIAbilityContext, path: string, name: string,
  bytes: number): Promise<void> {
  const suffix: RegExpMatchArray | null = name.toLowerCase().match(/\.[a-z0-9]+$/);
  const type: string = suffix ? utd.getUniformDataTypeByFilenameExtension(suffix[0]) : utd.UniformDataType.FILE;
  const data: systemShare.SharedData = new systemShare.SharedData({
    utd: type, uri: fileUri.getUriFromPath(path), title: name, description: formatAttachmentSize(bytes)
  });
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE,
    previewMode: systemShare.SharePreviewMode.DETAIL });
}

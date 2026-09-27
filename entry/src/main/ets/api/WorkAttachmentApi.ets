import { CourseResource } from '../data/ResourceModels';
import { cachedResource } from './ResourceCache';
import { send } from './HttpClient';
import { workAttachmentDownloadUrl } from './WorkAttachmentParser';

// Read-only metadata adapter. Actual bytes, cache and progress continue through
// the existing ResourceDownload / FileTransfer implementation without changes.
export async function prepareWorkAttachment(item: CourseResource, filesDir: string): Promise<void> {
  if (cachedResource(item, filesDir)) return;
  const response = await send({ url: 'https://mooc.mooc.ucas.edu.cn/ananas/status/' + encodeURIComponent(item.objectId ?? '') });
  item.downloadUrl = workAttachmentDownloadUrl(response.body, item.objectId ?? '');
}

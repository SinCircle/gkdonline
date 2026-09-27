import { CourseResource } from '../data/ResourceModels';

export interface ResourceTypeStyle { label: string; color: Resource; background: Resource; }

// Shared by course materials and chapter attachments. These are type badges, not thumbnails.
export function resourceTypeStyle(item: CourseResource): ResourceTypeStyle {
  if (item.work) return { label: 'WORK', color: $r('app.color.ui_type_doc'), background: $r('app.color.ui_type_doc_soft') };
  if (item.folder) return { label: 'DIR', color: $r('app.color.ui_type_folder'), background: $r('app.color.ui_type_folder_soft') };
  const suffix: RegExpMatchArray | null = item.name.toLowerCase().match(/\.([a-z0-9]+)$/);
  const type: string = suffix ? suffix[1] : item.type.toLowerCase().replace(/^\./, '');
  if (type === 'pdf') return { label: 'PDF', color: $r('app.color.ui_type_pdf'), background: $r('app.color.ui_type_pdf_soft') };
  if (['ppt', 'pptx', 'odp'].includes(type)) return { label: 'PPT', color: $r('app.color.ui_type_ppt'), background: $r('app.color.ui_type_ppt_soft') };
  if (['doc', 'docx', 'odt', 'rtf'].includes(type)) return { label: 'DOC', color: $r('app.color.ui_type_doc'), background: $r('app.color.ui_type_doc_soft') };
  if (['xls', 'xlsx', 'csv', 'ods'].includes(type)) return { label: 'XLS', color: $r('app.color.ui_type_xls'), background: $r('app.color.ui_type_xls_soft') };
  if (['mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', 'video'].includes(type)) return { label: 'VID', color: $r('app.color.ui_type_video'), background: $r('app.color.ui_type_video_soft') };
  if (['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'audio'].includes(type)) return { label: 'AUD', color: $r('app.color.ui_type_audio'), background: $r('app.color.ui_type_audio_soft') };
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'svg', 'image'].includes(type)) return { label: 'IMG', color: $r('app.color.ui_type_image'), background: $r('app.color.ui_type_image_soft') };
  if (['zip', 'rar', '7z', 'gz', 'tar', 'bz2', 'xz'].includes(type)) return { label: 'ZIP', color: $r('app.color.ui_type_archive'), background: $r('app.color.ui_type_archive_soft') };
  return { label: 'FILE', color: $r('app.color.ui_type_other'), background: $r('app.color.ui_type_other_soft') };
}

@ComponentV2
export struct ResourceTypeIcon {
  @Require @Param item: CourseResource;

  build() {
    Text(resourceTypeStyle(this.item).label)
      .fontSize($r('app.float.ui_text_label')).fontWeight(FontWeight.Medium)
      .fontColor(resourceTypeStyle(this.item).color).textAlign(TextAlign.Center)
      .width($r('app.float.ui_size_filter_control')).height($r('app.float.ui_size_filter_control'))
      .backgroundColor(resourceTypeStyle(this.item).background)
      .borderRadius($r('app.float.ui_radius_type_icon'))
      .id('resource-type-' + this.item.id)
  }
}

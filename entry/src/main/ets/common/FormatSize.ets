/** Format a byte count for display. Keep exact byte counts in transfer checks. */
export function formatAttachmentSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units: string[] = ['KB', 'MB', 'GB'];
  let size: number = bytes / 1024;
  let unit: number = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  const rounded: number = Math.round(size * 10) / 10;
  return `${rounded} ${units[unit]}`;
}

/** Add the same unit spacing to sizes already formatted by the course site. */
export function formatSizeLabel(label: string): string {
  const value: string = label.trim();
  if (/^\d+$/.test(value)) return formatAttachmentSize(Number(value));
  const match: RegExpMatchArray | null = value.match(/^(\d+(?:\.\d+)?)\s*([KMGT])B?$/i);
  if (match) return `${match[1]} ${match[2].toUpperCase()}B`;
  const bytes: RegExpMatchArray | null = value.match(/^(\d+(?:\.\d+)?)\s*B$/i);
  return bytes ? `${bytes[1]} B` : value;
}

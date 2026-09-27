// Inert HTML tree. No DOM, WebView, eval, script execution, form submission or subresource loading.
export class HtmlNode {
  tag: string = '';
  attrs: Record<string, string> = {};
  children: HtmlNode[] = [];
  text: string = '';
}
export function decodeHtml(value: string): string {
  const named: Record<string, string> = { 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
    'ensp': ' ', 'emsp': ' ', 'ndash': '–', 'mdash': '—', 'lsquo': '‘', 'rsquo': '’', 'ldquo': '“', 'rdquo': '”',
    'hellip': '…', 'middot': '·', 'times': '×', 'divide': '÷', 'le': '≤', 'ge': '≥', 'ne': '≠', 'plusmn': '±', 'deg': '°', 'copy': '©' };
  return value.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (original: string, key: string): string => {
    if (!key.startsWith('#')) return named[key] ?? original;
    const code: number = key[1].toLowerCase() === 'x' ? parseInt(key.substring(2), 16) : parseInt(key.substring(1), 10);
    return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : '�';
  });
}
export function parseHtml(html: string): HtmlNode {
  const root: HtmlNode = new HtmlNode();
  const stack: HtmlNode[] = [root];
  const inert: string = html.replace(/<!--[^]*?-->/g, '').replace(/<(script|style)\b[^>]*>[^]*?<\/\1\s*>/gi, '')
    .replace(/<(script|style)\b[^>]*>[^]*$/gi, '');
  const tokens: RegExp = /<\/?[a-zA-Z][^>"']*(?:(?:"[^"]*"|'[^']*')[^>"']*)*>|<![^>]*>|[^<]+|</g;
  let match: RegExpExecArray | null = tokens.exec(inert);
  while (match) {
    const token: string = match[0];
    if (token.startsWith('</')) {
      const tag: string = /^<\/\s*([^\s>]+)/.exec(token)?.[1].toLowerCase() ?? '';
      for (let index: number = stack.length - 1; index > 0; index--) {
        if (stack[index].tag === tag) { stack.length = index; break; }
      }
    } else if (!token.startsWith('<!')) {
      const node: HtmlNode = new HtmlNode();
      const opening: RegExpExecArray | null = /^<([a-zA-Z][\w:-]*)/.exec(token);
      if (opening) {
        node.tag = opening[1].toLowerCase();
        const attrs: RegExp = /([^\s=<>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
        const source: string = token.substring(opening[0].length, token.length - 1);
        let attr: RegExpExecArray | null = attrs.exec(source);
        while (attr) { node.attrs[attr[1].toLowerCase()] = decodeHtml(attr[2] ?? attr[3] ?? attr[4] ?? ''); attr = attrs.exec(source); }
      } else node.text = decodeHtml(token);
      stack[stack.length - 1].children.push(node);
      if (node.tag === 'textarea') {
        // A textarea is an HTML RCDATA element. Preserve embedded answer HTML as text,
        // then let the answer parser inspect it; otherwise attachment markup would be lost.
        const closing: RegExp = /<\/textarea\s*>/gi;
        closing.lastIndex = tokens.lastIndex;
        const end: RegExpExecArray | null = closing.exec(inert);
        const child: HtmlNode = new HtmlNode();
        child.text = decodeHtml(inert.substring(tokens.lastIndex, end ? end.index : inert.length));
        node.children.push(child);
        tokens.lastIndex = end ? closing.lastIndex : inert.length;
        match = tokens.exec(inert);
        continue;
      }
      if (node.tag && !['br', 'hr', 'img', 'input', 'meta', 'link', 'source', 'area', 'embed', 'wbr'].includes(node.tag) && !token.endsWith('/>')) stack.push(node);
    }
    match = tokens.exec(inert);
  }
  return root;
}
export function hasClass(node: HtmlNode, name: string): boolean { return (node.attrs['class'] ?? '').split(/\s+/).includes(name); }
export function findNodes(node: HtmlNode, predicate: (node: HtmlNode) => boolean): HtmlNode[] {
  const result: HtmlNode[] = [];
  for (const child of node.children) {
    if (predicate(child)) result.push(child);
    result.push(...findNodes(child, predicate));
  }
  return result;
}
export function plainNode(node: HtmlNode, exclude: string[] = []): string {
  if (exclude.some((name: string) => hasClass(node, name)) || ['script', 'style', 'iframe', 'input', 'textarea', 'button', 'img'].includes(node.tag)) return '';
  if (node.tag === 'br') return '\n';
  const value: string = node.tag || node.children.length > 0 ? node.children.map((child: HtmlNode) => plainNode(child, exclude)).join('') : node.text;
  if (node.tag === 'sup') return '^(' + value + ')';
  if (node.tag === 'sub') return '_(' + value + ')';
  return ['p', 'div', 'li', 'tr', 'h3', 'h2', 'pre'].includes(node.tag) ? value + '\n' : value;
}
export function cleanText(node: HtmlNode, exclude: string[] = []): string {
  return plainNode(node, exclude).replace(/[\t\r ]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}

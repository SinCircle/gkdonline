// Local-test-only URL mock. The device build uses @ohos.url from the SDK.
class MockURL {
  constructor(text, hostname) {
    this.text = text;
    this.hostname = hostname;
  }

  static parseURL(input, base) {
    let absolute = input;
    if (input.startsWith('//')) {
      absolute = base.substring(0, base.indexOf(':')) + ':' + input;
    } else if (input.indexOf('://') < 0) {
      const baseUrl = MockURL.parseURL(base);
      const origin = baseUrl.text.substring(0, baseUrl.text.indexOf('/', baseUrl.text.indexOf('://') + 3));
      const basePath = baseUrl.text.substring(origin.length).split('?')[0].split('#')[0];
      if (input.startsWith('/')) {
        absolute = origin + input;
      } else if (input.startsWith('?')) {
        absolute = origin + basePath + input;
      } else {
        const lastSlash = basePath.lastIndexOf('/');
        absolute = origin + basePath.substring(0, lastSlash + 1) + input;
      }
    }
    const schemeEnd = absolute.indexOf('://');
    if (schemeEnd < 0) throw new Error('Invalid URL');
    const scheme = absolute.substring(0, schemeEnd).toLowerCase();
    const authorityStart = schemeEnd + 3;
    const slash = absolute.indexOf('/', authorityStart);
    const question = absolute.indexOf('?', authorityStart);
    let authorityEnd = absolute.length;
    if (slash >= 0 && slash < authorityEnd) authorityEnd = slash;
    if (question >= 0 && question < authorityEnd) authorityEnd = question;
    const authority = absolute.substring(authorityStart, authorityEnd).toLowerCase();
    const hostname = authority.startsWith('[') ? authority.substring(0, authority.indexOf(']') + 1) :
      authority.split(':')[0];
    const suffix = absolute.substring(authorityEnd);
    const queryAt = suffix.indexOf('?');
    const path = queryAt >= 0 ? suffix.substring(0, queryAt) : suffix;
    const query = queryAt >= 0 ? suffix.substring(queryAt) : '';
    const segments = [];
    for (const part of path.split('/')) {
      if (part === '..') segments.pop();
      else if (part.length > 0 && part !== '.') segments.push(part);
    }
    const normalizedPath = '/' + segments.join('/') + (path.endsWith('/') && segments.length > 0 ? '/' : '');
    return new MockURL(scheme + '://' + authority + normalizedPath + query, hostname);
  }

  toString() {
    return this.text;
  }
}

export default { URL: MockURL };

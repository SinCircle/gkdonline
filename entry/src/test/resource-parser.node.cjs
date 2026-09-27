const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require(process.argv[2]);
const root = path.resolve(__dirname, '../../..');
const cache = new Map();
function load(file) {
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} }; cache.set(file, module);
  const result = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: file });
  new Function('require', 'module', 'exports', result.outputText)(id => load(path.resolve(path.dirname(file), id + '.ets')), module, module.exports);
  return module.exports;
}
const parser = load(path.join(root, 'entry/src/main/ets/api/ResourceParser.ets'));
const read = name => fs.readFileSync(path.join(root, 'entry/build/verification', name), 'utf8');
let passed = 0;
function test(name, run) { run(); passed++; console.log('PASS ' + name); }
const rows = JSON.parse(read('m3-round5/manifest.json')).filter(r => r.label.startsWith('chapters-'));
test('全部 46 份真实章节页：44 空目录，2 非空目录', () => {
  let nonempty = 0;
  for (const r of rows) {
    const result = parser.parseChapters(read('m3-round5/' + r.bodyFile), r.label.substring(9));
    if (result.chapters.length) { nonempty++; console.log(`${r.label}: ${result.chapters.length} rows, first=${result.chapters[0].title}`); }
  }
  assert.equal(nonempty, 2); assert.equal(rows.length, 46);
});
test('真实章节层级和名称', () => {
  const chapters = parser.parseChapters(read('m3-round5/18-chapters-350140000037185.txt'), '350140000037185').chapters;
  assert.equal(chapters[0].title, '第一单元'); assert.equal(chapters[0].group, true);
  assert.equal(chapters[1].number, '1.1'); assert.equal(chapters[1].title, '第一课时');
  assert.equal(chapters[2].id, '578270'); assert.equal(chapters[2].number, '1.1.1');
});

test('末章后没有 script 时仍取自身序号，不反向切片', () => {
  const html='<input id="courseId" value="1"><div id="fanyaChapter"><div class="chapter_item" id="cur101" title="前一章"><span class="catalog_sbar">9.1</span></div><div class="chapter_item" id="cur102" title="末章"><span class="catalog_sbar">9.2</span></div></div>';
  const chapters=parser.parseChapters(html,'1').chapters;
  assert.equal(chapters.length,2);assert.equal(chapters[1].number,'9.2');assert.equal(chapters[1].title,'末章');
});
test('真实资料页、空列表和文件夹', () => {
  const rows = JSON.parse(read('m3-round6/manifest.json')).filter(r => r.label.startsWith('data-'));
  for(const r of rows) { const data = parser.parseCourseResources(read('m3-round6/'+r.bodyFile),r.label.substring(5)); console.log(`${r.label}: ${data.items.length} items`); }
  const data = parser.parseCourseResources(read('m3-round7/04-physics-folder.txt'), '350140000039689');
  assert.equal(data.items.length, 5); assert.equal(data.items[0].name,'免费软件资源介绍.docx');
  assert(data.items.every(i=>!i.folder));
  const ai=parser.parseCourseResources(read('m3-round6/09-data-350140000041203.txt'),'350140000041203');
  assert.equal(ai.items[0].name,'第五讲-神经网络与深度学习.pdf'); assert.equal(ai.items[0].size,'2MB');
  assert.match(ai.items[0].downloadUrl,/downloadData\?dataId=350140900373404&classId=/);
  const doubleQuotes=read('m3-round6/09-data-350140000041203.txt').replace(/href='([^']*\/downloadData[^']*)'/g,'href="$1"');
  assert.equal(parser.parseCourseResources(doubleQuotes,'350140000041203').items[0].downloadUrl,ai.items[0].downloadUrl);
});
test('章节媒体元数据、空附件页、结束哨兵区分', () => {
  const card=parser.parseChapterCard(read('m3-round7/01-chapter-cards-ucas.txt'),'578270');
  assert.equal(card.items.length,1); assert.equal(card.items[0].name,'1-1：欧洲理想社会主义的发展与历史局限性.mp4');
  assert.equal(card.items[0].size,'698.8 MB'); assert(card.cardId);
  const end=parser.parseChapterCard(read('m3-round7/03-chapter-cards-one.txt'),'578270'); assert.equal(end.cardId,'');
  const parent=parser.parseChapterCard(read('m3-round7/05-cards-parent.txt'),'578262'); assert(parent.cardId); assert.equal(parent.items.length,0);
  assert.equal(parser.parseChapterCard(read('m4-work-lists3/49-military-card.txt'),'577492').items.length,0);
});
test('错误正文、错课程/章节、结构缺损不显示为空', () => {
  for(const text of ['<html>登录</html>','', '<html>无效的参数</html>']) {
    assert.throws(()=>parser.parseChapters(text,'1'), e=>e.kind==='parse');
    assert.throws(()=>parser.parseCourseResources(text,'1'), e=>e.kind==='parse');
    assert.throws(()=>parser.parseChapterCard(text,'1'), e=>e.kind==='parse');
  }
  assert.throws(()=>parser.parseChapters(read('m3-round5/18-chapters-350140000037185.txt'),'1'),e=>e.kind==='parse');
  assert.throws(()=>parser.parseChapterCard(read('m3-round7/01-chapter-cards-ucas.txt').replace('"attachments":','"missing":'),'578270'),e=>e.kind==='parse');
});
console.log(`Tests: ${passed}, passed: ${passed}, failed: 0`);

// 隔离 HTTP 与会话服务，检验新资源读取器的失败传播和分页；不读写设备凭证。
async function apiChecks() {
  const {ApiError,ApiErrorKind} = load(path.join(root,'entry/src/main/ets/api/errors.ets'));
  let loggedIn = true;
  let reply;
  const requests=[];
  cache.set(path.join(root,'entry/src/main/ets/auth/SessionManager.ets'),{exports:{SessionManager:{get:()=>({loggedIn})}}});
  cache.set(path.join(root,'entry/src/main/ets/api/HttpClient.ets'),{exports:{send:async spec=>{requests.push(spec.url);return reply(spec);}}});
  const api=load(path.join(root,'entry/src/main/ets/api/ResourceApi.ets'));
  const course={courseId:'350140000037185',classId:'350140000031930',cpi:'350140000217951'};
  const route={course,chapterId:'578270',folderId:'0',parentId:'0',enc:''};
  loggedIn=false;
  await assert.rejects(()=>api.fetchChapters(course),e=>e.kind==='session-expired');
  assert.equal(requests.length,0);
  loggedIn=true;
  reply=()=>{throw new ApiError(ApiErrorKind.NETWORK,'isolated network failure')};
  await assert.rejects(()=>api.fetchChapters(course),e=>e.kind==='network');
  reply=spec=>({body:read(spec.url.includes('num=0')?'m3-round7/01-chapter-cards-ucas.txt':'m3-round7/03-chapter-cards-one.txt')});
  const data=await api.fetchChapterResources(route);assert.equal(data.items.length,1);
  reply=spec=>{if(spec.url.includes('num=1'))throw new ApiError(ApiErrorKind.NETWORK,'second page failed');return {body:read('m3-round7/01-chapter-cards-ucas.txt')}};
  await assert.rejects(()=>api.fetchChapterResources(route),e=>e.kind==='network');
  reply=()=>({body:read('m3-round7/01-chapter-cards-ucas.txt')});
  await assert.rejects(()=>api.fetchChapterResources(route),e=>e.kind==='parse');
  console.log('PASS API 隔离验证：未登录不请求、网络失败传播、完整分页、后续页失败不返回部分结果、重复页拒绝');
}
apiChecks().catch(error=>{console.error(error);process.exitCode=1;});

// 用本机 DevEco TypeScript 编译器执行生产解析器；不连接设备、不读写会话。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require(process.argv[2]);
const root = path.resolve(__dirname, '../../..');
const cache = new Map();
function load(file) {
  if (cache.has(file)) return cache.get(file).exports;
  const module = { exports: {} };
  cache.set(file, module);
  const result = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: file,
  });
  new Function('require', 'module', 'exports', result.outputText)(
    id => load(path.resolve(path.dirname(file), id + '.ets')), module, module.exports);
  return module.exports;
}
const parser = load(path.join(root, 'entry/src/main/ets/api/CourseParser.ets'));
const body = fs.readFileSync(path.join(root, 'entry/build/verification/backclazzdata-full.json'), 'utf8');
const html = fs.readFileSync(path.join(root, 'entry/build/verification/m2-course-page.html'), 'utf8');
let passed = 0;
function test(name, run) { run(); passed++; console.log('PASS ' + name); }
function rejects(body, page = html) {
  assert.throws(() => parser.buildCourseCatalog(body, page), e => e.kind === 'parse');
}
test('真实 46 门课程、教师和缺失作业计数', () => {
  const catalog = parser.buildCourseCatalog(body, html);
  assert.equal(catalog.courses.length, 46);
  assert.equal(catalog.courses[0].name, '低年级研讨课II（数学与应用数学）');
  assert.equal(catalog.courses[0].teacher, '邓富声');
  assert(catalog.courses.every(c => c.unfinishedWorkCount === undefined));
});
test('学校当前学期与三个真实筛选分组', () => {
  const catalog = parser.buildCourseCatalog(body, html);
  assert.equal(catalog.currentSemesterId, '28');
  assert.equal(parser.filterCourses(catalog.courses, '').length, 46);
  for (const [id, count, label] of [
    ['28', 13, '2026-2027秋季学期'], ['26', 18, '2025-2026春季学期'], ['25', 15, '2025-2026秋季学期'],
  ]) {
    const filtered = parser.filterCourses(catalog.courses, id);
    assert.equal(filtered.length, count);
    assert(filtered.every(c => c.semester === label));
  }
  assert.equal(parser.filterCourses(catalog.courses, '27').length, 0);
  assert.equal(catalog.courses[30].beginDate, '2026-01-05 04:37');
  assert.equal(catalog.courses[30].semester, '2025-2026秋季学期');
});
test('HTML 类型头不参与 JSON 正文解析', () => {
  assert.equal(parser.parseCourseList('\n ' + body).length, 46);
});
test('合法空列表与损坏或失败响应明确区分', () => {
  assert.equal(parser.parseCourseList('{"result":1,"channelList":[]}').length, 0);
  for (const text of ['<html>登录</html>', '{bad', 'null', '[]', '{"result":0}',
    '{"result":1,"channelList":[{}]}']) rejects(text);
  const data = JSON.parse(body); data.hasMore = true; rejects(JSON.stringify(data));
});
test('缺失字段保持为空，未知学期不能冒充已知学期', () => {
  const data = JSON.parse(body);
  delete data.channelList[0].content.course.data[0].teacherfactor;
  delete data.channelList[0].content.course.data[0].sectionId;
  const first = parser.buildCourseCatalog(JSON.stringify(data), html).courses[0];
  assert.equal(first.teacher, ''); assert.equal(first.semester, '');
  data.channelList[0].content.course.data[0].sectionId = 999;
  rejects(JSON.stringify(data));
});
test('学期页结构变化产生解析错误，不能显示空课程', () => {
  rejects(body, '<html>登录页面</html>');
  const reordered = html.replaceAll('sectionId="28" semesterNum="20261"',
    'semesterNum="20261" sectionId="28"');
  assert.equal(parser.buildCourseCatalog(body, reordered).currentSemesterId, '28');
});
console.log(`Tests: ${passed}, passed: ${passed}, failed: 0`);

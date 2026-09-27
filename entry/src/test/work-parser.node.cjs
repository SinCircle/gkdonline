const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require(process.argv[2]);
const root = path.resolve(__dirname, '../../..');
const cache = new Map();
function load(file) {
  if(cache.has(file)) return cache.get(file).exports;
  const module={exports:{}}; cache.set(file,module);
  const compiled=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020},fileName:file});
  new Function('require','module','exports',compiled.outputText)(id=>id==='@kit.CoreFileKit'?{fileIo:{accessSync:fs.existsSync,readTextSync:p=>fs.readFileSync(p,'utf8'),unlinkSync:fs.unlinkSync}}:load(path.resolve(path.dirname(file),id+'.ets')),module,module.exports);
  return module.exports;
}
const parser=load(path.join(root,'entry/src/main/ets/api/WorkParser.ets'));
const read=name=>fs.readFileSync(path.join(root,'entry/build/verification',name),'utf8');
const records=JSON.parse(read('m4-work-lists3/manifest.json')).filter(r=>r.label.startsWith('work-list-'));
let nonempty=0,total=0;
for(const r of records){
  const html=read('m4-work-lists3/'+r.bodyFile);
  const course={courseId:r.label.substring(10),classId:/id="classId" value="([^"]+)"/.exec(html)[1],cpi:'350140000217951'};
  const items=parser.parseWorkList(html,course);
  assert.equal(items.length,(html.match(/onclick="goTask\(this\);"/g)||[]).length);
  if(items.length) nonempty++;
  total+=items.length;
  const entry=JSON.parse(read('m4-work-entry3/manifest.json')).find(e=>e.label==='entry-'+course.courseId);
  const url=parser.workListUrl(read('m4-work-entry3/'+entry.bodyFile),course);
  assert(url.includes('courseId='+course.courseId)); assert(url.includes('classId='+course.classId));
}
assert.equal(records.length,46); assert.equal(nonempty,11);
console.log(`PASS real samples: 46 courses, 11 nonempty, ${total} work items, entry signatures match`);
for(const record of JSON.parse(read('m4-work-page2/manifest.json'))){
  const html=read('m4-work-page2/'+record.bodyFile);
  const course={courseId:record.label.substring('page2-work-list-'.length),classId:/id="classId" value="([^"]+)"/.exec(html)[1]};
  const page=parser.workPageInfo(html);assert.deepEqual(page,{current:2,total:2});
  const items=parser.parseWorkList(html,course);assert(items.length>0);total+=items.length;
}
console.log(`PASS both real second pages; ${total} total course work items`);
const html=read('m4-work-lists3/07-work-list-350140000039778.txt');
const course={courseId:'350140000039778',classId:'350140000034557'};
const items=parser.parseWorkList(html,course);
assert.equal(items[0].title,'ENGLIV_ResearchProjectExploration');assert.equal(items[0].status,'未交');
assert.match(items[0].deadlineText,/^剩余\d+小时\d+分钟$/);assert.equal(items[1].status,'待批阅');assert.equal(items[1].deadlineText,'');
for(const bad of ['', '<html>登录</html>', read('m4-work-lists/01-work-list-350140000041203.txt'), html.replace('class="status fl"','class="missing"'), html.replace('$("#page").html("")','unknownPagination()')]){
  assert.throws(()=>parser.parseWorkList(bad,course),e=>e.kind==='parse');
}
assert.throws(()=>parser.parseWorkList(html,{courseId:'wrong',classId:course.classId}),e=>e.kind==='parse');
console.log('PASS title/status/deadline semantics; login, denied, malformed, wrong-course and unknown pagination rejected');
async function apiChecks(){
  const {ApiError,ApiErrorKind}=load(path.join(root,'entry/src/main/ets/api/errors.ets'));
  let loggedIn=false, failure=false;
  const requests=[];
  cache.set(path.join(root,'entry/src/main/ets/auth/SessionManager.ets'),{exports:{SessionManager:{get:()=>({loggedIn})}}});
  cache.set(path.join(root,'entry/src/main/ets/api/FileTransfer.ets'),{exports:{transferFile:async(url,p)=>{
    requests.push(url);
    if(failure && url.includes('pageNum=2')) throw new ApiError(ApiErrorKind.NETWORK,'isolated offline');
    const fixture=url.includes('stucoursemiddle')?'m4-work-entry3/26-entry-350140000036361.txt':url.includes('pageNum=2')?'m4-work-page2/01-page2-work-list-350140000036361.txt':'m4-work-lists3/26-work-list-350140000036361.txt';
    fs.writeFileSync(p,read(fixture));
  }}});
  const api=load(path.join(root,'entry/src/main/ets/api/WorkApi.ets'));
  const dir=path.join(root,'entry/build/verification/work-test-cache');fs.mkdirSync(dir,{recursive:true});
  const course={courseId:'350140000036361',classId:'350140000031089',cpi:'350140000217951'};
  await assert.rejects(()=>api.fetchCourseWork(course,dir),e=>e.kind==='session-expired');assert.equal(requests.length,0);
  loggedIn=true;
  const items=await api.fetchCourseWork(course,dir);assert.equal(items.length,16);assert.equal(requests.length,3);
  failure=true;await assert.rejects(()=>api.fetchCourseWork(course,dir),e=>e.kind==='network');
  assert.equal(fs.readdirSync(dir).length,0);
  console.log('PASS Work API: unauthenticated makes no request; 16 items across 2 pages; later failure rejects partial result; temporary files cleaned');
}
apiChecks().catch(e=>{console.error(e);process.exitCode=1;});

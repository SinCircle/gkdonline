import { parseWorkAttachments } from './WorkAttachmentParser';
import { attachmentAnswerHtml } from './WorkUploadParser';
import { WorkQuestion, QuestionKind, WorkSubmissionForm, WorkField, AnswerBinding, AnswerChoice, WorkAnswer } from '../data/WorkDetailModels';
import { HtmlNode, parseHtml, findNodes, cleanText, decodeHtml, hasClass } from './WorkHtml';
import { resolveUrl, hostOf } from '../common/UrlUtil';
import { ApiError, ApiErrorKind } from './errors';

function invalid(message: string): ApiError { return new ApiError(ApiErrorKind.PARSE, message); }
function byId(root: HtmlNode, id: string): HtmlNode | undefined { return findNodes(root, (n: HtmlNode) => n.attrs['id'] === id)[0]; }
function rawText(node: HtmlNode): string { return node.text + node.children.map((child: HtmlNode) => rawText(child)).join(''); }
function scriptFunction(html: string, name: string, next: string): string {
  const start: number = html.indexOf('function ' + name + '(');
  const end: number = html.indexOf('function ' + next + '(', start + 1);
  return start >= 0 && end > start ? html.substring(start, end).replace(/\s+/g, '') : '';
}

// The submitted page supplies its own GET navigation for revising an answer.
// Accept only a literal string concatenation from modifyAnswer; never run its JavaScript.
export function parseWorkModifyUrl(html: string): string {
  const body: string = /function\s+modifyAnswer\s*\(\s*\)\s*\{([\s\S]*?)\}/.exec(html)?.[1] ?? '';
  const expression: string = /location\.href\s*=\s*([^;]+);/.exec(body)?.[1] ?? '';
  if (!/^\s*(?:"[^"\\]*"|'[^'\\]*')(?:\s*\+\s*(?:"[^"\\]*"|'[^'\\]*'))*\s*$/.test(expression)) return '';
  const parts: RegExpMatchArray | null = expression.match(/"[^"\\]*"|'[^'\\]*'/g);
  if (!parts) return '';
  const target: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', parts.map((part: string) => part.substring(1, part.length - 1)).join(''));
  if (hostOf(target) !== 'mooc.mooc.ucas.edu.cn' || !target.startsWith('https://mooc.mooc.ucas.edu.cn/mooc-ans/mooc2/work/dowork?')) return '';
  const query: string = target.substring(target.indexOf('?') + 1);
  const pairs: string[] = query.split('&');
  const keys: string[] = pairs.map((pair: string) => pair.split('=')[0]);
  if (new Set(keys).size !== keys.length || /[#\s]/.test(query)) return '';
  for (const name of ['courseId', 'classId', 'cpi', 'workId', 'answerId']) {
    const value: string = pairs.find((pair: string) => pair.startsWith(name + '='))?.substring(name.length + 1) ?? '';
    if (!/^[1-9]\d*$/.test(value)) return '';
  }
  for (const name of ['standardEnc', 'enc']) {
    const value: string = pairs.find((pair: string) => pair.startsWith(name + '='))?.substring(name.length + 1) ?? '';
    if (!/^[a-fA-F0-9]{32}$/.test(value)) return '';
  }
  if (!keys.includes('knowledgeId') || !keys.includes('jobid')) return '';
  return target;
}

// Parses HTML and reads known script literals as text. Never executes page JavaScript.
export function parseWorkSubmission(html: string, questions: WorkQuestion[]): WorkSubmissionForm | undefined {
  const root: HtmlNode = parseHtml(html);
  const pageTitle: string = cleanText(findNodes(root, (n: HtmlNode) => n.tag === 'title')[0] ?? new HtmlNode());
  const form: HtmlNode | undefined = byId(root, 'submitForm');
  // A graded/read-only page cannot become writable because it contains other form tags.
  if (pageTitle !== '作业作答' || !form) return undefined;
  if (form.tag !== 'form' || form.attrs['method']?.toLowerCase() !== 'post') throw invalid('未识别的提交表单');
  const action: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', form.attrs['action'] ?? '');
  if (hostOf(action) !== 'mooc.mooc.ucas.edu.cn' || !action.startsWith('https://mooc.mooc.ucas.edu.cn/mooc-ans/work/addStudentWorkNewWeb?')) throw invalid('提交地址未通过校验');
  const fields: WorkField[] = [];
  const controls: HtmlNode[] = findNodes(form, (n: HtmlNode) => ['input', 'textarea', 'select', 'button'].includes(n.tag) && !!n.attrs['name'] && n.attrs['disabled'] === undefined);
  const names: Set<string> = new Set<string>();
  let blocked: string = '';
  for (const input of controls) {
    const name: string = input.attrs['name'];
    if (names.has(name)) throw invalid('存在未识别的同名表单字段，不能猜测编码');
    names.add(name);
    const type: string = input.attrs['type'] ?? '';
    if (input.tag === 'input' && type === 'hidden') fields.push({ name: name, value: input.attrs['value'] ?? '', source: 'HTML hidden#' + (input.attrs['id'] ?? name) });
    else if (input.tag === 'textarea') fields.push({ name: name, value: rawText(input), source: 'HTML textarea#' + (input.attrs['id'] ?? name) });
    else blocked = '表单含尚未验证的输入字段，暂不能提交';
  }
  for (const name of ['courseId', 'classId', 'knowledgeid', 'cpi', 'workRelationId', 'workAnswerId', 'jobid', 'standardEnc', 'enc_work', 'totalQuestionNum', 'pyFlag', 'answerwqbid', 'mooc2', 'randomOptions', 'workTimesEnc']) {
    if (!names.has(name)) throw invalid('提交表单缺少字段：' + name);
  }
  const qids: string = /var\s+qids\s*=\s*"([\d,]+)"/.exec(html)?.[1] ?? '';
  if (qids !== questions.map((q: WorkQuestion) => q.id + ',').join('')) throw invalid('提交题号列表与题目不一致');
  const questionIds: WorkField | undefined = fields.find((f: WorkField) => f.name === 'answerwqbid');
  if (questionIds) { questionIds.value = qids; questionIds.source = '页面 ready2Submit 的 qids 字面量'; }
  const compact: string = html.replace(/\s+/g, '');
  // Exact serialization contract observed in all eight writable forms. Unknown templates fail closed.
  const protocol: boolean = compact.includes("url+='&ua='+clientType();") && compact.includes("url+='&formType='+getformType();") &&
    compact.includes("url+='&saveStatus='+1;") && compact.includes("url+='&version=1';") && compact.includes('varua="pc";') &&
    compact.includes('return"post";') && compact.includes('$("#submitForm").serialize()');
  if (!protocol) blocked = '服务端提交序列化规则已变化，暂不能提交';
  const limit: number = Number(byId(root, 'limitWorkSubmitTimes')?.attrs['value'] ?? '100');
  if (Number(byId(root, 'addTimes')?.attrs['value'] ?? '0') > limit) blocked = '服务端要求验证码，暂不支持在原生页面提交';
  const bindings: AnswerBinding[] = [];
  for (const q of questions) {
    const node: HtmlNode | undefined = byId(form, 'question' + q.id);
    const answer: HtmlNode | undefined = byId(form, 'answer' + q.id);
    const type: HtmlNode | undefined = byId(form, 'answertype' + q.id);
    const binding: AnswerBinding = { questionId: q.id, name: answer?.attrs['name'] ?? '', mode: '', initial: '', choices: [], reason: '' };
    if (!node || !answer || !type || type.attrs['name'] !== 'answertype' + q.id || !binding.name || !names.has(binding.name)) {
      binding.reason = '没有可识别的答案字段';
    } else if ((q.kind === QuestionKind.SHORT && type.attrs['value'] === '4') || (q.kind === QuestionKind.ESSAY && type.attrs['value'] === '6')) {
      if (answer.tag !== 'textarea') binding.reason = '文本题的提交控件尚未识别';
      else {
        const existing: string = rawText(answer);
        const existingRoot: HtmlNode = parseHtml(existing);
        const unsupported: boolean = findNodes(existingRoot, (n: HtmlNode) => ['img', 'object', 'embed', 'audio', 'video', 'math', 'svg'].includes(n.tag) || (n.tag === 'iframe' && n.attrs['module'] !== 'insertAttach')).length > 0;
        if (unsupported) binding.reason = '已有答案包含尚未支持的图片或公式，不能覆盖';
        else {
          binding.mode = 'text';
          binding.initial = cleanText(existingRoot); binding.initialAttachments = parseWorkAttachments(existingRoot);
        }
      }
    } else if (q.kind === QuestionKind.SINGLE || q.kind === QuestionKind.MULTIPLE || q.kind === QuestionKind.JUDGMENT) {
      // Option codes must occur explicitly in the writable DOM, never inferred from A/B or 对/错.
      const fn: string = q.kind === QuestionKind.MULTIPLE ? scriptFunction(html, 'addMultipleChoice', 'sortMultiAnswer') : scriptFunction(html, 'addChoice', 'addMultipleChoice');
      const known: boolean = fn.includes('choiceContent=choiceContent+$(this).attr("data");') && fn.includes('$("#answer"+qid).val(choiceContent);');
      const optionNodes: HtmlNode[] = findNodes(node, (n: HtmlNode) => hasClass(n, 'choice' + q.id) && n.attrs['data'] !== undefined);
      for (const opt of optionNodes) {
        const value: string = opt.attrs['data'];
        const label: string = cleanText(opt);
        const match = q.options.find((o) => o.label === label.replace(/[.、．]/g, ''));
        if (q.kind === QuestionKind.JUDGMENT) {
          if (!['对', '错', '正确', '错误'].includes(label)) continue;
          binding.choices.push({ label: ['对', '正确'].includes(label) ? '对' : '错', text: '', value: value });
        } else if (match) binding.choices.push({ label: match.label, text: match.text, value: value });
      }
      if (!known || answer.attrs['type'] !== 'hidden' || binding.choices.length !== (q.kind === QuestionKind.JUDGMENT ? 2 : q.options.length) || binding.choices.length < 2 ||
        binding.choices.some((c: AnswerChoice) => !/^[A-Za-z0-9]$/.test(c.value)) || new Set(binding.choices.map((c: AnswerChoice) => c.value)).size !== binding.choices.length) {
        binding.reason = '尚未取得并识别本题可提交的选项编码';
      } else {
        binding.mode = q.kind === QuestionKind.MULTIPLE ? 'multiple' : 'single';
        binding.initial = answer.attrs['value'] ?? '';
      }
    } else binding.reason = '暂不支持的题型，保留原题干';
    if (binding.reason) blocked = '第 ' + q.number + ' 题：' + binding.reason;
    bindings.push(binding);
  }
  const field = (name: string): string => fields.find((f: WorkField) => f.name === name)?.value ?? '';
  const key: string = [field('cpi'), field('courseId'), field('classId'), field('workRelationId'), field('workAnswerId')].join('-');
  if (!/^[\d-]+$/.test(key)) throw invalid('提交对象编号未通过校验');
  return { action: action + '&ua=pc&formType=post&saveStatus=1&version=1', fields: fields, bindings: bindings, key: key, blockedReason: blocked };
}

export function submissionFields(form: WorkSubmissionForm, answers: WorkAnswer[]): WorkField[] {
  if (form.blockedReason) throw invalid(form.blockedReason);
  return form.fields.map((field: WorkField): WorkField => {
    const binding: AnswerBinding | undefined = form.bindings.find((b: AnswerBinding) => b.name === field.name);
    if (!binding) return { name: field.name, value: field.value, source: field.source };
    const answer: WorkAnswer | undefined = answers.find((a: WorkAnswer) => a.questionId === binding.questionId);
    if (!answer) throw invalid('缺少题目答案状态');
    let value: string = answer.value;
    if (binding.mode !== 'text' && binding.mode !== 'attachment') {
      if (binding.mode === 'single' && value.length > 1) throw invalid('单选或判断题不能选择多项');
      if (value.split('').some((v: string) => !binding.choices.some((c: AnswerChoice) => c.value === v))) throw invalid('选项编码无效');
      value = Array.from(new Set(value.split(''))).sort().join('');
    } else {
      // UE's content is HTML. Escape all entered text; preserve lines, never treat input as markup.
      value = value ? '<p>' + value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/\r?\n/g, '<br/>') + '</p>' : '';
    }
    if (binding.mode === 'text' || binding.mode === 'attachment') {
      value += (answer.attachments ?? []).map((file) => attachmentAnswerHtml(file)).join('');
    }
    return { name: field.name, value: value, source: '原生作答及附件 → HTML #' + binding.name };
  });
}
export function encodeWorkFields(fields: WorkField[]): string {
  return fields.map((f: WorkField) => encodeURIComponent(f.name) + '=' + encodeURIComponent(f.value)).join('&');
}

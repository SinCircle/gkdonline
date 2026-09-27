import { parseWorkUploadPlan } from './WorkUploadParser';
import { parseWorkAttachments } from './WorkAttachmentParser';
import { parseWorkSubmission } from './WorkFormParser';
import { WorkDetail, WorkQuestion, QuestionKind, QuestionOption, QuestionAttachment } from '../data/WorkDetailModels';
import { HtmlNode, parseHtml, hasClass, findNodes, cleanText } from './WorkHtml';
import { ApiError, ApiErrorKind } from './errors';
import { resolveUrl, hostOf } from '../common/UrlUtil';

function invalid(message: string): ApiError { return new ApiError(ApiErrorKind.PARSE, message); }
function firstClass(node: HtmlNode, name: string): HtmlNode | undefined { return findNodes(node, (n: HtmlNode) => hasClass(n, name))[0]; }
function previousAnswer(node: HtmlNode): string {
  const myAnswer: HtmlNode | undefined = firstClass(node, 'myAnswer');
  if (myAnswer) return cleanText(myAnswer);
  const content: HtmlNode | undefined = firstClass(node, 'stuAnswerContent');
  if (!content) return '';
  let text: string = cleanText(content);
  for (const attachment of findNodes(content, (n: HtmlNode) => n.tag === 'iframe')) {
    if (!attachment.attrs['filename']) text += '\n[已有附件尚未识别]';
  }
  if (findNodes(content, (n: HtmlNode) => ['img', 'svg', 'math'].includes(n.tag)).length) text += '\n[已有答案含图片或公式，暂不支持预览]';
  return text.trim() ? '我的答案：\n' + text.trim() : (parseWorkAttachments(content).length ? '我的答案：附件' : '我的答案：页面未提供文本答案');
}
function kindOf(name: string): QuestionKind {
  switch (name) {
    case '单选题': return QuestionKind.SINGLE;
    case '多选题': return QuestionKind.MULTIPLE;
    case '填空题': return QuestionKind.BLANK;
    case '判断题': return QuestionKind.JUDGMENT;
    case '简答题': return QuestionKind.SHORT;
    case '论述题': return QuestionKind.ESSAY;
    default: return QuestionKind.UNSUPPORTED;
  }
}
export function parseWorkDetail(html: string): WorkDetail {
  const root: HtmlNode = parseHtml(html);
  const pageTitle: string = cleanText(findNodes(root, (n: HtmlNode) => n.tag === 'title')[0] ?? new HtmlNode());
  if (/登录|login/i.test(pageTitle)) throw ApiError.sessionExpired('作业详情返回登录页');
  const titleNode: HtmlNode | undefined = firstClass(root, 'mark_title') ?? firstClass(root, 'ceyan_name');
  const title: string = titleNode ? cleanText(titleNode.tag === 'h2' ? titleNode : findNodes(titleNode, (n: HtmlNode) => n.tag === 'h3')[0] ?? titleNode) : '';
  const questionNodes: HtmlNode[] = findNodes(root, (n: HtmlNode) => /^question\d+$/.test(n.attrs['id'] ?? '') &&
    (hasClass(n, 'questionLi') || hasClass(n, 'TiMu')));
  if (!title || !/作业|详情/.test(pageTitle)) throw invalid('未取得已识别的作业详情页面');
  const text: string = cleanText(root);
  const declared: RegExpExecArray | null = /题量\s*[:：]\s*(\d+)/.exec(text);
  const groups: HtmlNode[] = findNodes(root, (n: HtmlNode) => hasClass(n, 'type_tit') || hasClass(n, 'newTestType'));
  const groupCount: number = groups.reduce((sum: number, n: HtmlNode) => sum + Number(/共\s*(\d+)\s*题/.exec(cleanText(n))?.[1] ?? 0), 0);
  if (declared && Number(declared[1]) !== questionNodes.length) throw invalid('题量与返回的题目数量不一致，不能展示不完整详情');
  if (groupCount > 0 && groupCount !== questionNodes.length) throw invalid('题型分组题量不匹配');
  if (questionNodes.length === 0 && (!declared || Number(declared[1]) !== 0)) throw invalid('页面未提供可识别的题目，不能当成空作业');
  const questions: WorkQuestion[] = [];
  for (const node of questionNodes) {
    const id: string = node.attrs['id'].replace('question', '');
    if (questions.some((q: WorkQuestion) => q.id === id)) throw invalid('题目编号重复');
    const header: HtmlNode | undefined = firstClass(node, 'mark_name') ?? firstClass(node, 'Zy_TItle');
    if (!header) throw invalid('题干标题结构尚未识别');
    const headerText: string = cleanText(header);
    const number: string = /^\s*(\d+)/.exec(headerText)?.[1] ?? '';
    if (!number) throw invalid('原始题号缺失');
    const typeText: string = cleanText(firstClass(header, 'colorShallow') ?? firstClass(header, 'newZy_TItle') ?? new HtmlNode());
    const sourceType: string = /[（(【]\s*([^,，)）】]+)/.exec(typeText)?.[1].trim() ?? node.attrs['typename'] ?? '';
    if (node.attrs['typename'] && node.attrs['typename'] !== sourceType) throw invalid('页面题型声明冲突');
    let kind: QuestionKind = kindOf(sourceType);
    const points: string = /[,，]\s*([\d.]+)\s*分/.exec(typeText)?.[1] ?? '';
    const content: HtmlNode = firstClass(header, 'qtContent') ?? header;
    let stem: string = cleanText(content, ['colorShallow', 'newZy_TItle']);
    if (content === header) stem = stem.replace(/^\s*\d+\s*[.、．]?\s*/, '');
    const options: QuestionOption[] = [];
    if (kind === QuestionKind.SINGLE || kind === QuestionKind.MULTIPLE) {
      const list: HtmlNode | undefined = firstClass(node, 'Zy_ulTop') ?? firstClass(node, 'stem_answer');
      if (!list) throw invalid('选择题选项结构未识别');
      // Text-only options must never silently lose a formula, picture or embedded attachment.
      if (findNodes(list, (n: HtmlNode) => ['img', 'svg', 'math', 'iframe', 'object', 'embed', 'canvas'].includes(n.tag)).length > 0 || /\p{Private_Use}/u.test(cleanText(list))) {
        throw invalid(`第 ${number} 题选项包含尚未支持的图片或公式，不能展示不完整选项`);
      }
      for (const li of findNodes(list, (n: HtmlNode) => n.tag === 'li')) {
        const option: RegExpExecArray | null = /^([A-Z])[、.．]?\s*([^]*)$/.exec(cleanText(li));
        if (!option || !option[2].trim()) throw invalid('选择题选项缺失或未识别');
        options.push({ label: option[1], text: option[2].trim() });
      }
      if (options.length < 2 || new Set(options.map((o: QuestionOption) => o.label)).size !== options.length) throw invalid('选择题选项不完整或重复');
    } else if (kind === QuestionKind.JUDGMENT) {
      // A judgment stays a judgment. Do not infer an A/B choice or expose earned points as question points.
    } else if (kind === QuestionKind.BLANK) {
      // Preserve the stem's existing blank notation; never invent a blank count from underscores.
    } else if (kind === QuestionKind.SHORT) {
      // Read-only stem and attachments; no editor, auto-save or submission in this milestone.
    }
    const attachments: QuestionAttachment[] = [];
    for (const iframe of findNodes(content, (n: HtmlNode) => n.tag === 'iframe')) {
      if (iframe.attrs['module'] !== 'insertAttach' || !iframe.attrs['filename'] || !iframe.attrs['objectid']) {
        kind = QuestionKind.UNSUPPORTED; continue;
      }
      attachments.push({ name: iframe.attrs['filename'], type: iframe.attrs['filetype'] ?? '', objectId: iframe.attrs['objectid'] });
    }
    const images: string[] = [];
    for (const image of findNodes(content, (n: HtmlNode) => n.tag === 'img')) {
      const url: string = resolveUrl('https://mooc.mooc.ucas.edu.cn', image.attrs['src'] ?? '');
      if (/^https:\/\//.test(url) && ['cs.mooc.ucas.edu.cn', 'mooc.mooc.ucas.edu.cn'].includes(hostOf(url))) images.push(url);
      else { kind = QuestionKind.UNSUPPORTED; stem += '\n[题干包含尚未支持的图片来源]'; }
    }
    if (/\p{Private_Use}/u.test(stem) || findNodes(content, (n: HtmlNode) => ['svg', 'math', 'object', 'embed', 'canvas'].includes(n.tag)).length > 0) kind = QuestionKind.UNSUPPORTED;
    if (!stem && !images.length && !attachments.length && kind !== QuestionKind.UNSUPPORTED) throw invalid('题干为空或尚未识别');
    questions.push({ id: id, number: number, kind: kind, sourceType: sourceType, points: points,
      stem: stem, options: options, attachments: parseWorkAttachments(content), images: images,
      answerAttachments: parseWorkAttachments(firstClass(node, 'stuAnswerContent') ?? firstClass(node, 'myAnswer') ?? new HtmlNode()),
      previousAnswer: previousAnswer(node) });
  }
  const form = parseWorkSubmission(html, questions);
  const serverState: string = cleanText(firstClass(root, 'testTit_status') ?? new HtmlNode());
  return { title: title, description: cleanText(firstClass(root, 'infoHead') ?? firstClass(root, 'ceyan_top') ?? new HtmlNode()), questions: questions,
    state: form ? (form.blockedReason ? '未提交 · 含暂不支持的作答内容' : '未提交 · 可作答') : (serverState || pageTitle) + ' · 只读', form: form, upload: form ? parseWorkUploadPlan(html) : undefined };
}

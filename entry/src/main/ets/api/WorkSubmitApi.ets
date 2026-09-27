import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SessionManager } from '../auth/SessionManager';
import { WorkSubmissionForm, WorkAnswer, WorkField } from '../data/WorkDetailModels';
import { submissionFields, encodeWorkFields } from './WorkFormParser';
import { send } from './HttpClient';
import { isLoginRedirect } from './RedirectRules';
import { resolveUrl } from '../common/UrlUtil';
import { saveProbeText } from './TransferProbe';
import { ApiError, ApiErrorKind } from './errors';

export interface WorkSubmitResult { outcome: string; message: string; status: number; body: string; }
interface SubmitResponse { status: boolean | number; msg?: string; stuStatus?: number; }
interface ValidateResponse { status: number; }
interface SubmitReceipt { time: string; action: string; fields: WorkField[]; result: WorkSubmitResult; }
const inFlight: Set<string> = new Set<string>();
function directory(filesDir: string): string {
  const path: string = filesDir + '/work-submissions';
  if (!fs.accessSync(path)) fs.mkdirSync(path, true);
  return path;
}
export function previousSubmission(filesDir: string, form: WorkSubmissionForm): WorkSubmitResult | undefined {
  const path: string = directory(filesDir) + '/' + form.key + '.json';
  if (!fs.accessSync(path)) return undefined;
  try { return (JSON.parse(fs.readTextSync(path)) as SubmitReceipt).result; }
  catch (_) { return { outcome: 'uncertain', message: '本机提交记录无法读取，请先核实服务端状态，避免重复提交', status: 0, body: '' }; }
}
export function loadWorkDraft(filesDir: string, form: WorkSubmissionForm): WorkAnswer[] {
  const path: string = directory(filesDir) + '/' + form.key + '.draft.json';
  try {
    if (fs.accessSync(path)) {
      const saved: WorkAnswer[] = JSON.parse(fs.readTextSync(path)) as WorkAnswer[];
      return form.bindings.map((b) => ({ questionId: b.questionId, value: saved.find((a) => a.questionId === b.questionId)?.value ?? b.initial, attachments: saved.find((a) => a.questionId === b.questionId)?.attachments ?? b.initialAttachments ?? [] } as WorkAnswer));
    }
  } catch (_) {}
  return form.bindings.map((b) => ({ questionId: b.questionId, value: b.initial, attachments: b.initialAttachments ?? [] } as WorkAnswer));
}
export function saveWorkDraft(filesDir: string, form: WorkSubmissionForm, answers: WorkAnswer[]): void {
  saveProbeText(directory(filesDir) + '/' + form.key + '.draft.json', JSON.stringify(answers));
}
function header(headers: Object, name: string): string {
  const record: Record<string, string> = headers as Record<string, string>;
  const key: string | undefined = Object.keys(record).find((k: string) => k.toLowerCase() === name);
  return key ? record[key] : '';
}
export function interpretSubmitResponse(status: number, body: string, location: string): WorkSubmitResult {
  if (status === 401 || status === 403 || (location && isLoginRedirect(resolveUrl('https://mooc.mooc.ucas.edu.cn', location))) || /<title[^>]*>[^<]*(登录|login)/i.test(body)) {
    return { outcome: 'login', message: '登录已失效，请登录后重新读取作业状态', status: status, body: body };
  }
  try {
    const data: SubmitResponse = JSON.parse(body) as SubmitResponse;
    if (status >= 200 && status < 300 && (data.status === true || data.status === 1)) {
      return { outcome: 'success', message: data.stuStatus === 5 ? '提交成功；服务端提示未达到通过标准，请返回查看作业状态' : '提交成功' + (data.msg ? '：' + data.msg : ''), status: status, body: body };
    }
    if (data.status === false || data.status === 0) {
      const message: string = data.msg || '服务端拒绝提交，但没有提供原因';
      return { outcome: /重新登录|未登录|登录失效/.test(message) ? 'login' : 'failure', message: message, status: status, body: body };
    }
  } catch (_) {}
  return { outcome: 'uncertain', message: `HTTP ${status}：未取得可确认的提交结果，请先核实作业状态，勿重复提交`, status: status, body: body };
}

// Exactly one POST, no retries, no redirect replay, no auto-save or statistics calls.
export async function submitWork(form: WorkSubmissionForm, answers: WorkAnswer[], filesDir: string): Promise<WorkSubmitResult> {
  if (inFlight.has(form.key)) throw new Error('正在提交，请勿重复操作');
  const previous: WorkSubmitResult | undefined = previousSubmission(filesDir, form);
  if (previous && ['success', 'pending', 'uncertain'].includes(previous.outcome)) throw new Error('这份作业已有提交记录，请先核实服务端状态');
  if (!SessionManager.get().loggedIn) return { outcome: 'login', message: '请先登录', status: 0, body: '' };
  const fields: WorkField[] = submissionFields(form, answers);
  const value = (name: string): string => fields.find((f: WorkField) => f.name === name)?.value ?? '';
  inFlight.add(form.key);
  let dispatched: boolean = false;
  const receipt: SubmitReceipt = { time: new Date().toISOString(), action: form.action, fields: fields,
    result: { outcome: 'pending', message: '已开始提交，结果待确认', status: 0, body: '' } };
  const path: string = directory(filesDir) + '/' + form.key + '.json';
  let request: http.HttpRequest | undefined = undefined;
  try {
    // This GET and its status mapping are copied from the observed submitValidate function.
    const validation = await send({ url: 'https://mooc.mooc.ucas.edu.cn/mooc-ans/work/validate?courseId=' + encodeURIComponent(value('courseId')) + '&classId=' + encodeURIComponent(value('classId')) + '&cpi=' + encodeURIComponent(value('cpi')) });
    const validity: ValidateResponse = JSON.parse(validation.body) as ValidateResponse;
    if (validity.status === 1) return { outcome: 'login', message: '账号发生异常，请重新登录', status: validation.status, body: validation.body };
    if (validity.status !== 2 && validity.status !== 3) return { outcome: 'failure', message: '服务端账号校验未通过：' + validation.body.substring(0, 200), status: validation.status, body: validation.body };
    // Record intent before sending, so leaving/restarting cannot accidentally resend an ambiguous request.
    saveProbeText(path, JSON.stringify(receipt, null, 2));
    request = http.createHttp();
    dispatched = true;
    const response: http.HttpResponse = await request.request(form.action, {
      method: http.RequestMethod.POST, maxRedirects: 0, connectTimeout: 10000, readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING,
      header: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Cookie': SessionManager.get().cookieHeaderFor('mooc.mooc.ucas.edu.cn'),
        'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 gkdOnline/1.0', 'Accept': 'application/json' },
      extraData: encodeWorkFields(fields)
    });
    receipt.result = interpretSubmitResponse(response.responseCode, typeof response.result === 'string' ? response.result : '', header(response.header, 'location'));
    saveProbeText(path, JSON.stringify(receipt, null, 2));
    return receipt.result;
  } catch (error) {
    if (!dispatched && error instanceof ApiError && error.kind === ApiErrorKind.SESSION_EXPIRED) {
      return { outcome: 'login', message: '登录已失效，请登录后重新读取作业状态', status: error.status, body: '' };
    }
    const result: WorkSubmitResult = { outcome: dispatched ? 'uncertain' : 'failure', status: 0, body: '',
      message: dispatched ? '提交后连接中断或记录失败，结果尚不确定；请核实服务端状态，勿重复提交' : '尚未发送提交请求：' + (error as Error).message };
    if (dispatched) { receipt.result = result; try { saveProbeText(path, JSON.stringify(receipt, null, 2)); } catch (_) {} }
    return result;
  } finally { request?.destroy(); inFlight.delete(form.key); }
}

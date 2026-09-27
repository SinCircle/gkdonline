export enum QuestionKind {
  SINGLE = '单选题', MULTIPLE = '多选题', BLANK = '填空题', JUDGMENT = '判断题', SHORT = '简答题', ESSAY = '论述题', UNSUPPORTED = '暂不支持的题型'
}
export interface QuestionOption { label: string; text: string; }
export interface QuestionAttachment { name: string; type: string; objectId: string; size?: string; }
export interface WorkQuestion {
  id: string; number: string; kind: QuestionKind; sourceType: string; points: string;
  stem: string; options: QuestionOption[]; attachments: QuestionAttachment[]; images: string[]; answerAttachments: QuestionAttachment[]; previousAnswer: string;
}
export interface WorkField { name: string; value: string; source: string; }
export interface AnswerChoice { label: string; text: string; value: string; }
export interface AnswerBinding { questionId: string; name: string; mode: string; initial: string; initialAttachments?: QuestionAttachment[]; choices: AnswerChoice[]; reason: string; }
export interface WorkSubmissionForm { action: string; fields: WorkField[]; bindings: AnswerBinding[]; key: string; blockedReason: string; }
export interface WorkAnswer { questionId: string; value: string; attachments?: QuestionAttachment[]; }
export interface WorkDetail { title: string; description: string; questions: WorkQuestion[]; state: string; form?: WorkSubmissionForm; upload?: WorkUploadPlan; }

export interface WorkUploadPlan { url: string; maxBytes: number; }

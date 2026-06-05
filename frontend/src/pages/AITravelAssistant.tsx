import { ChangeEvent, FormEvent, useRef, useState } from "react";
import axios from "axios";
import { useMutation } from "@tanstack/react-query";
import { Bot, FileText, Paperclip, Send, X } from "lucide-react";

import { api, formatFileSize, uploadDocumentToS3 } from "../api/client";
import PageHeader from "../components/PageHeader";
import { ChatMessage, TravelDocument } from "../types";

export default function AITravelAssistant() {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      role: "assistant",
      content: "Tell me where you are going, your dates, budget, and what you want to optimize."
    }
  ]);
  const [question, setQuestion] = useState("");
  const [attachments, setAttachments] = useState<TravelDocument[]>([]);
  const [uploadError, setUploadError] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const mutation = useMutation({
    mutationFn: async ({ nextQuestion, documentIds }: { nextQuestion: string; documentIds: string[] }) =>
      (await api.post<{ answer: string }>("/ai/chat", { question: nextQuestion, document_ids: documentIds })).data,
    onSuccess: (data) => {
      setMessages((current) => [...current, { role: "assistant", content: data.answer }]);
      inputRef.current?.focus();
    },
    onError: (error) => {
      const detail = axios.isAxiosError(error) ? error.response?.data?.detail : undefined;
      const message =
        typeof detail === "string"
          ? detail
          : "I could not reach the travel assistant service. Check that the backend is running on port 8080.";
      setMessages((current) => [...current, { role: "assistant", content: message }]);
    }
  });

  const uploadMutation = useMutation({
    mutationFn: async (file: File) =>
      uploadDocumentToS3({
        file,
        presignPath: "/documents/chat/presign-upload",
        completePath: (documentId) => `/documents/chat/${documentId}/complete`,
        documentType: "chat_attachment"
      }),
    onSuccess: (document) => {
      setAttachments((current) => [...current, document].slice(-5));
      setUploadError("");
    },
    onError: (error) => {
      const detail = axios.isAxiosError(error) ? error.response?.data?.detail : undefined;
      setUploadError(typeof detail === "string" ? detail : "Could not upload attachment.");
    }
  });

  const deleteAttachmentMutation = useMutation({
    mutationFn: async (documentId: string) => api.delete(`/documents/chat/${documentId}`)
  });

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    const trimmed = question.trim();
    if (!trimmed) {
      return;
    }
    if (trimmed.length < 3) {
      setMessages((current) => [
        ...current,
        { role: "user", content: trimmed },
        { role: "assistant", content: "Please enter at least 3 characters." }
      ]);
      setQuestion("");
      return;
    }
    const sentAttachments = attachments;
    setMessages((current) => [...current, { role: "user", content: trimmed, attachments: sentAttachments }]);
    setQuestion("");
    setAttachments([]);
    mutation.mutate({ nextQuestion: trimmed, documentIds: sentAttachments.map((attachment) => attachment.id) });
  };

  const handleFileChange = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) {
      return;
    }
    uploadMutation.mutate(file);
  };

  const removeAttachment = (documentId: string) => {
    setAttachments((current) => current.filter((item) => item.id !== documentId));
    deleteAttachmentMutation.mutate(documentId);
  };

  return (
    <div>
      <PageHeader title="AI Travel Assistant" description="Ask trip planning, routing, safety, budget, and timing questions." />

      <section className="flex min-h-[calc(100vh-160px)] flex-col rounded-lg border border-zinc-200 bg-white">
        <div className="flex-1 space-y-4 overflow-y-auto p-4">
          {messages.map((message, index) => (
            <div key={`${message.role}-${index}`} className={`flex ${message.role === "user" ? "justify-end" : "justify-start"}`}>
              <div
                className={[
                  "max-w-3xl whitespace-pre-line rounded-lg px-4 py-3 text-sm leading-6",
                  message.role === "user" ? "bg-teal-700 text-white" : "bg-zinc-100 text-zinc-800"
                ].join(" ")}
              >
                {message.role === "assistant" && (
                  <div className="mb-2 flex items-center gap-2 text-xs font-semibold text-zinc-600">
                    <Bot className="h-4 w-4" aria-hidden="true" />
                    Assistant
                  </div>
                )}
                {message.content}
                {message.attachments && message.attachments.length > 0 && (
                  <div className="mt-3 space-y-2">
                    {message.attachments.map((attachment) => (
                      <div key={attachment.id} className="flex items-center gap-2 rounded-lg bg-white/15 px-2 py-1 text-xs">
                        <FileText className="h-3.5 w-3.5" aria-hidden="true" />
                        <span className="truncate">{attachment.file_name}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ))}
          {mutation.isPending && <div className="text-sm text-zinc-500">Assistant is thinking...</div>}
        </div>

        <form onSubmit={handleSubmit} className="space-y-3 border-t border-zinc-200 p-4">
          {(attachments.length > 0 || uploadError || uploadMutation.isPending) && (
            <div className="flex flex-wrap gap-2">
              {attachments.map((attachment) => (
                <span key={attachment.id} className="inline-flex max-w-full items-center gap-2 rounded-lg border border-zinc-200 bg-zinc-50 px-2 py-1 text-xs text-zinc-700">
                  <FileText className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                  <span className="truncate">
                    {attachment.file_name} - {formatFileSize(attachment.size_bytes)}
                  </span>
                  <button type="button" aria-label={`Remove ${attachment.file_name}`} onClick={() => removeAttachment(attachment.id)}>
                    <X className="h-3.5 w-3.5" aria-hidden="true" />
                  </button>
                </span>
              ))}
              {uploadMutation.isPending && <span className="rounded-lg bg-zinc-100 px-2 py-1 text-xs text-zinc-600">Uploading attachment</span>}
              {uploadError && <span className="rounded-lg bg-rose-50 px-2 py-1 text-xs text-rose-700">{uploadError}</span>}
            </div>
          )}

          <div className="flex gap-2">
            <input
              ref={inputRef}
              className="field"
              value={question}
              onChange={(event) => setQuestion(event.target.value)}
              placeholder="Ask about routes, budgets, hotels, packing, or weather"
              minLength={3}
            />
            <input ref={fileInputRef} type="file" className="hidden" onChange={handleFileChange} />
            <button
              type="button"
              className="secondary-button px-3"
              disabled={uploadMutation.isPending || attachments.length >= 5}
              aria-label="Attach file"
              onClick={() => fileInputRef.current?.click()}
            >
              <Paperclip className="h-4 w-4" aria-hidden="true" />
            </button>
            <button type="submit" className="primary-button px-3" disabled={mutation.isPending || uploadMutation.isPending || !question.trim()} aria-label="Send message">
              <Send className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}

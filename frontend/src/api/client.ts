import axios from "axios";

import { PresignedUploadResponse, TravelDocument } from "../types";

export const TOKEN_STORAGE_KEY = "ai_travel_token";
export const USER_STORAGE_KEY = "ai_travel_user";
const defaultApiBaseUrl = import.meta.env.DEV ? "http://localhost:8080/api" : "/api";

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || defaultApiBaseUrl,
  timeout: 45000
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_STORAGE_KEY);
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export function formatCurrency(value: string | number | undefined): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0
  }).format(Number(value ?? 0));
}

export function formatDate(value: string): string {
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    year: "numeric"
  }).format(new Date(value));
}

export function formatFileSize(sizeBytes: number): string {
  if (sizeBytes < 1024) {
    return `${sizeBytes} B`;
  }
  if (sizeBytes < 1024 * 1024) {
    return `${(sizeBytes / 1024).toFixed(1)} KB`;
  }
  return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
}

export async function uploadDocumentToS3({
  file,
  presignPath,
  completePath,
  documentType
}: {
  file: File;
  presignPath: string;
  completePath: (documentId: string) => string;
  documentType: string;
}): Promise<TravelDocument> {
  const contentType = file.type || inferContentType(file.name);
  const { data } = await api.post<PresignedUploadResponse>(presignPath, {
    file_name: file.name,
    content_type: contentType,
    size_bytes: file.size,
    document_type: documentType
  });

  await axios.put(data.upload_url, file, {
    headers: data.headers,
    timeout: 120000,
    withCredentials: false
  });

  return (await api.post<TravelDocument>(completePath(data.document.id), {})).data;
}

function inferContentType(fileName: string): string {
  const extension = fileName.split(".").pop()?.toLowerCase();
  switch (extension) {
    case "pdf":
      return "application/pdf";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "png":
      return "image/png";
    case "webp":
      return "image/webp";
    case "txt":
      return "text/plain";
    case "md":
      return "text/markdown";
    case "json":
      return "application/json";
    case "csv":
      return "text/csv";
    default:
      return "application/octet-stream";
  }
}

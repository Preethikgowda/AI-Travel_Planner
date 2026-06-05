import { ChangeEvent, FormEvent, useEffect, useMemo, useState } from "react";
import axios from "axios";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Download, FileText, ShieldCheck, Trash2, Upload } from "lucide-react";

import { api, formatDate, formatFileSize, uploadDocumentToS3 } from "../api/client";
import EmptyState from "../components/EmptyState";
import PageHeader from "../components/PageHeader";
import { TravelDocument, Trip } from "../types";

const documentTypes = [
  { value: "flight_ticket", label: "Flight ticket" },
  { value: "hotel_booking", label: "Hotel booking" },
  { value: "visa", label: "Visa" },
  { value: "insurance", label: "Insurance" },
  { value: "passport_copy", label: "Passport copy" },
  { value: "receipt", label: "Receipt" },
  { value: "itinerary", label: "Itinerary" },
  { value: "general", label: "General" }
];

function errorMessage(error: unknown, fallback: string): string {
  const detail = axios.isAxiosError(error) ? error.response?.data?.detail : undefined;
  return typeof detail === "string" ? detail : fallback;
}

export default function TripDocuments() {
  const queryClient = useQueryClient();
  const [selectedTripId, setSelectedTripId] = useState("");
  const [documentType, setDocumentType] = useState("flight_ticket");
  const [file, setFile] = useState<File | null>(null);
  const [uploadError, setUploadError] = useState("");

  const tripsQuery = useQuery({
    queryKey: ["trips"],
    queryFn: async () => (await api.get<Trip[]>("/trips")).data
  });

  const trips = tripsQuery.data ?? [];

  useEffect(() => {
    if (!selectedTripId && trips.length > 0) {
      setSelectedTripId(trips[0].id);
    }
  }, [selectedTripId, trips]);

  const selectedTrip = useMemo(() => trips.find((trip) => trip.id === selectedTripId), [selectedTripId, trips]);

  const documentsQuery = useQuery({
    queryKey: ["trip-documents", selectedTripId],
    queryFn: async () => (await api.get<TravelDocument[]>(`/trips/${selectedTripId}/documents`)).data,
    enabled: Boolean(selectedTripId)
  });

  const uploadMutation = useMutation({
    mutationFn: async () => {
      if (!file || !selectedTripId) {
        throw new Error("Choose a trip and file.");
      }
      return uploadDocumentToS3({
        file,
        presignPath: `/trips/${selectedTripId}/documents/presign-upload`,
        completePath: (documentId) => `/trips/${selectedTripId}/documents/${documentId}/complete`,
        documentType
      });
    },
    onSuccess: () => {
      setFile(null);
      setUploadError("");
      queryClient.invalidateQueries({ queryKey: ["trip-documents", selectedTripId] });
    },
    onError: (error) => {
      setUploadError(errorMessage(error, "Could not upload document."));
    }
  });

  const deleteMutation = useMutation({
    mutationFn: async (documentId: string) => api.delete(`/trips/${selectedTripId}/documents/${documentId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["trip-documents", selectedTripId] });
    }
  });

  const downloadMutation = useMutation({
    mutationFn: async (documentId: string) =>
      (await api.get<{ download_url: string }>(`/trips/${selectedTripId}/documents/${documentId}/download-url`)).data,
    onSuccess: (data) => {
      window.open(data.download_url, "_blank", "noopener,noreferrer");
    }
  });

  const handleFileChange = (event: ChangeEvent<HTMLInputElement>) => {
    setFile(event.target.files?.[0] ?? null);
    setUploadError("");
  };

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    uploadMutation.mutate();
  };

  const documents = documentsQuery.data ?? [];

  return (
    <div>
      <PageHeader title="Trip Documents" description="Store private travel documents with S3 object storage and KMS encryption." />

      {trips.length === 0 ? (
        <EmptyState title="No trips available">Create a trip before uploading documents.</EmptyState>
      ) : (
        <div className="grid gap-5 xl:grid-cols-[0.75fr_1.25fr]">
          <form onSubmit={handleSubmit} className="space-y-4 rounded-lg border border-zinc-200 bg-white p-4">
            <label className="block space-y-2">
              <span className="label">Trip</span>
              <select className="field" value={selectedTripId} onChange={(event) => setSelectedTripId(event.target.value)}>
                {trips.map((trip) => (
                  <option key={trip.id} value={trip.id}>
                    {trip.destination}
                  </option>
                ))}
              </select>
            </label>

            <label className="block space-y-2">
              <span className="label">Document type</span>
              <select className="field" value={documentType} onChange={(event) => setDocumentType(event.target.value)}>
                {documentTypes.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
            </label>

            <label className="block space-y-2">
              <span className="label">File</span>
              <input className="field" type="file" onChange={handleFileChange} />
            </label>

            {file && (
              <div className="rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm text-zinc-700">
                {file.name} - {formatFileSize(file.size)}
              </div>
            )}

            {uploadError && <div className="rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700">{uploadError}</div>}

            <button type="submit" className="primary-button w-full" disabled={uploadMutation.isPending || !file || !selectedTripId}>
              <Upload className="h-4 w-4" aria-hidden="true" />
              {uploadMutation.isPending ? "Uploading" : "Upload Document"}
            </button>
          </form>

          <section className="rounded-lg border border-zinc-200 bg-white p-4">
            <div className="mb-4 flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-lg font-semibold text-zinc-950">{selectedTrip?.destination ?? "Trip"} Documents</h2>
                <p className="text-sm text-zinc-600">{documents.length} encrypted file{documents.length === 1 ? "" : "s"}</p>
              </div>
              <div className="inline-flex items-center gap-2 rounded-lg bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-700">
                <ShieldCheck className="h-4 w-4" aria-hidden="true" />
                SSE-KMS
              </div>
            </div>

            {documents.length === 0 ? (
              <EmptyState title="No documents uploaded" />
            ) : (
              <div className="space-y-2">
                {documents.map((document) => (
                  <article key={document.id} className="grid gap-3 rounded-lg border border-zinc-200 p-3 md:grid-cols-[40px_1fr_auto] md:items-center">
                    <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-sky-50 text-sky-700">
                      <FileText className="h-4 w-4" aria-hidden="true" />
                    </div>
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-zinc-950">{document.file_name}</p>
                      <p className="text-sm text-zinc-600">
                        {document.document_type.replace(/_/g, " ")} - {formatFileSize(document.size_bytes)} - {formatDate(document.created_at)}
                      </p>
                    </div>
                    <div className="flex gap-2">
                      <button
                        type="button"
                        className="secondary-button h-10 w-10 p-0"
                        aria-label={`Download ${document.file_name}`}
                        onClick={() => downloadMutation.mutate(document.id)}
                      >
                        <Download className="h-4 w-4" aria-hidden="true" />
                      </button>
                      <button
                        type="button"
                        className="danger-button h-10 w-10 p-0"
                        aria-label={`Delete ${document.file_name}`}
                        onClick={() => deleteMutation.mutate(document.id)}
                      >
                        <Trash2 className="h-4 w-4" aria-hidden="true" />
                      </button>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}

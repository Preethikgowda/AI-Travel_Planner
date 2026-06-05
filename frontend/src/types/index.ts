export interface User {
  id: string;
  name: string;
  email: string;
  created_at: string;
}

export interface AuthResponse {
  access_token: string;
  token_type: string;
  user: User;
}

export interface Preference {
  id: string;
  user_id: string;
  travel_style: string;
  preferred_budget: string | number;
  interests: string[];
  created_at: string;
}

export interface Trip {
  id: string;
  user_id: string;
  destination: string;
  budget: string | number;
  days: number;
  interests: string[];
  status: string;
  created_at: string;
}

export interface Expense {
  id: string;
  trip_id: string;
  category: string;
  amount: string | number;
  description: string;
  created_at: string;
}

export interface BudgetSummary {
  total_budget: string | number;
  total_spent: string | number;
  remaining_budget: string | number;
}

export interface DayPlan {
  day: number;
  title: string;
  morning: string;
  afternoon: string;
  evening: string;
}

export interface ItineraryResponse {
  trip_summary: string;
  day_wise_plan: DayPlan[];
  estimated_budget_breakdown: Record<string, string>;
  travel_tips: string[];
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  attachments?: TravelDocument[];
}

export interface TravelDocument {
  id: string;
  user_id: string;
  trip_id: string | null;
  document_scope: "trip" | "chat";
  document_type: string;
  file_name: string;
  content_type: string;
  size_bytes: number;
  checksum_sha256: string | null;
  s3_bucket: string;
  s3_key: string;
  kms_key_id: string;
  status: string;
  created_at: string;
  uploaded_at: string | null;
  deleted_at: string | null;
}

export interface PresignedUploadResponse {
  document: TravelDocument;
  upload_url: string;
  method: "PUT";
  headers: Record<string, string>;
  expires_at: string;
  max_size_bytes: number;
}

export interface DestinationComparison {
  cost_comparison: Record<string, string>;
  weather_comparison: Record<string, string>;
  activity_comparison: Record<string, string>;
  best_choice: string;
}

export interface PackingCategory {
  category: string;
  items: string[];
}

export interface PackingResponse {
  packing_list: PackingCategory[];
}

export interface WeatherResponse {
  city: string;
  temperature_c: number;
  feels_like_c: number;
  humidity: number;
  condition: string;
  wind_speed_mps: number;
  source: string;
}

export interface HotelRecommendation {
  name: string;
  address: string;
  rating: number | null;
  price_level: number | null;
  open_now: boolean | null;
}

export interface HotelResponse {
  city: string;
  hotels: HotelRecommendation[];
  source: string;
}
